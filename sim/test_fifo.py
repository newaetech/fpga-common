import cocotb
from cocotb.triggers import RisingEdge, ClockCycles, Join, Lock, Event
from cocotb.clock import Clock
from cocotb.queue import Queue
from cocotb.handle import Force, Release
from cocotb.log import SimLogFormatter
#from cocotb.regression import TestFactory
import random
import math
import logging
import os

# Note: this could also be place in individual test functions by replacing root_logger by dut._log.
root_logger = logging.getLogger()
logfile = os.getenv('LOGFILE', 'make.log')
print('Logfile = %s' % logfile)
fh = logging.FileHandler(logfile, 'w')
fh.setFormatter(SimLogFormatter())
root_logger.addHandler(fh)

class Harness(object):
    def __init__(self, dut, reps, full_threshold, empty_threshold):
        self.dut = dut
        self.reps = reps
        self.tests = []
        self.errors = 0
        # Actual seed is obtained only if RANDOM_SEED is defined on vvp command line (otherwise you get 0)
        # regress.py always specifies the seed so this is fine.
        self.dut._log.info("seed: %d" % int(os.getenv('RANDOM_SEED', '0')))
        rclk_period = random.randint(4, 20)
        wclk_period = random.randint(4, 20)
        self.dut._log.info("rclk frequency randomized to %5.1f MHz" % (1/rclk_period*1000))
        self.dut._log.info("wclk frequency randomized to %5.1f MHz" % (1/wclk_period*1000))
        main_clk_thread = cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
        rclk_thread = cocotb.start_soon(Clock(dut.rclk, rclk_period, units="ns").start())
        wclk_thread = cocotb.start_soon(Clock(dut.wclk, wclk_period, units="ns").start())
        #  initialize all DUT input values:
        self.dut.wen.value = 0
        self.dut.ren.value = 0
        self.dut.rst_n.value = 1
        self.dut.full_threshold_value.value = full_threshold
        self.dut.empty_threshold_value.value = empty_threshold


    async def reset(self):
        # NOTE: the Xilinx FIFO simulation models are quite sensitive to the reset timing. They can misbehave and refuse
        # to reset properly. Logfile will contain complaints of "RST must be held high for at least...", even if the stated
        # rules are followed, and the empty/full status flags may remain at X. Sometimes just changing the time when the
        # reset begins, and how long it is held for, can return correct behaviour.
        await ClockCycles(self.dut.clk, 30)
        self.dut.rst_n.value = 0
        await ClockCycles(self.dut.clk, 10)
        self.dut.rst_n.value = 1

    def register_test(self, test):
        """ Add to list of running tests, so that we can later wait for all of
        them to complete via all_tests_done().
        """
        self.tests.append(test)

    async def all_tests_done(self):
        """ Wait for all tests which were registered via register_test() to finish.
        """
        for test in self.tests:
            await test.done()
        await ClockCycles(self.dut.clk, 10) # to give time for fifo_watch errors to be seen

    def start_tests(self):
        """ Wait for all tests which were registered via register_test() to finish.
        """
        for test in self.tests:
            test.start()

    def inc_error(self):
        self.errors += 1
        self.dut.errors.value = self.errors

    @staticmethod
    def hexstring(string, max_chars=24):
        """ Convenience function to put a string onto the simulation waveform."""
        data = 0
        for i,j in enumerate(string[:max_chars]):
            data += (ord(j) << ((max_chars-1-i)*8))
        return data


class FifoTest(object):
    def __init__(self, dut, harness, name, fwft, sync, depth, full_threshold, empty_threshold, dut_full, dut_empty, dut_almost_full, dut_almost_empty, dut_write, dut_wdata, dut_read, dut_rdata, dut_overflow, dut_underflow, dut_full_threshold, dut_empty_threshold):
        self.dut = dut
        self.harness = harness
        self.name = name
        self.fwft = fwft
        self.sync = sync
        self.depth = depth
        self.full_threshold = full_threshold
        self.empty_threshold = empty_threshold
        self.dut_full = dut_full
        self.dut_empty = dut_empty
        self.dut_almost_full = dut_almost_full
        self.dut_almost_empty = dut_almost_empty
        self.dut_write = dut_write
        self.dut_read = dut_read
        self.dut_wdata = dut_wdata
        self.dut_rdata = dut_rdata
        self.dut_overflow = dut_overflow
        self.dut_underflow = dut_underflow
        self.dut_full_threshold = dut_full_threshold
        self.dut_empty_threshold = dut_empty_threshold
        self._coro = None
        self._wcoro = None
        self._rcoro = None
        self._ccoro = None
        self._ocoro = None
        self._ucoro = None
        self.errors = 0
        self.max_burst = 10
        self.min_burst = 1
        self.max_idle = 10
        self.min_idle = 1
        self._fifo_data_queue = Queue(maxsize=depth+1)
        self._reads_allowed = Queue()
        self.actual_fill_state = 0
        self.read_done = False
        if sync:
            self.rclk = dut.clk
            self.wclk = dut.clk
            self.fill_state_slop = 1
        else:
            self.rclk = dut.rclk
            self.wclk = dut.wclk
            self.fill_state_slop = 18

    def start(self) -> None:
        """Start test thread"""
        if self._coro is not None:
            raise RuntimeError("Capture already started")
        self._coro = cocotb.start_soon(self._run())

    def stop(self) -> None:
        """Stop test thread"""
        if self._coro is None:
            raise RuntimeError("Capture never started")
        self._coro.kill()
        self._coro = None

    def running(self) -> bool:
        if self._coro is None or self._coro.done():
            return False
        else:
            return True

    async def done(self) -> None:
        """ wait for _run() to complete """
        await Join(self._coro)
        if int(self.dut.xilinx_mismatches_out.value) > 0:
            self.dut._log.warning("%d mismatches with Xilinx FIFO seen." % self.dut.xilinx_mismatches_out.value)
        if self.errors:
            self.dut._log.error("%6s test done, failed with %d errors" % (self.name, self.errors))
        else:
            self.dut._log.info("%6s test done: passed!" % self.name)

    async def _run(self) -> None:
        self.dut._log.debug('_run starting')
        self._wcoro = cocotb.start_soon(self._write_thread())
        self._rcoro = cocotb.start_soon(self._read_thread())
        self._ccoro = cocotb.start_soon(self._check_thread())
        self._ocoro = cocotb.start_soon(self._over_thread())
        self._ucoro = cocotb.start_soon(self._under_thread())
        await Join(self._wcoro)

    async def _write_thread(self) -> None:
        self.dut._log.debug('%6s _write_thread starting' % self.name)
        await RisingEdge(self.dut.rst_n)
        await ClockCycles(self.wclk, 25)
        for _ in range(self.harness.reps):
            # Run through a few distinct phases:
            #1- play around the empty point
            self.dut._log.debug('*** %6s TEST 1 ***' % self.name)
            self.dut.test_phase.value = self.harness.hexstring("%6s phase 1" % self.name)
            extra_rw = random.randint(100, 200)
            await self._do_writes(0)
            await self._wait_read_done()

            # 2- play around the empty threshold point
            self.dut._log.debug('*** %6s TEST 2 ***' % self.name)
            self.dut.test_phase.value = self.harness.hexstring("%6s phase 2" % self.name)
            await self._do_writes(self.empty_threshold)
            await self._wait_read_done()

            # 3- play around the full threshold point
            self.dut._log.debug('*** %6s TEST 3 ***' % self.name)
            self.dut.test_phase.value = self.harness.hexstring("%6s phase 3" % self.name)
            await self._do_writes(self.full_threshold)
            await self._wait_read_done()

            # 4- play around the full point
            self.dut._log.debug('*** %6s TEST 4 ***' % self.name)
            self.dut.test_phase.value = self.harness.hexstring("%6s phase 4" % self.name)
            await self._do_writes(512)
            await self._wait_read_done()

            # 5- precisely test programmable empty threshold
            self.dut._log.debug('*** %6s TEST 5 ***' % self.name)
            self.dut.test_phase.value = self.harness.hexstring("%6s phase 5" % self.name)
            await self._do_writes(self.empty_threshold-1, self.dut_empty_threshold, self.rclk, [1, 1, 0])
            await ClockCycles(self.wclk, 100)
            await self._wait_read_done()

            # 6- precisely test programmable full threshold
            self.dut._log.debug('*** %6s TEST 6 ***' % self.name)
            self.dut.test_phase.value = self.harness.hexstring("%6s phase 6" % self.name)
            await self._do_writes(self.full_threshold-1, self.dut_full_threshold, self.rclk, [0, 1, 1])
            await ClockCycles(self.wclk, 100)
            await self._wait_read_done()

            # 7- precisely test almost full
            self.dut._log.debug('*** %6s TEST 7 ***' % self.name)
            self.dut.test_phase.value = self.harness.hexstring("%6s phase 7" % self.name)
            await self._do_writes(self.depth-2, self.dut_almost_full, self.rclk, [0, 1])
            await ClockCycles(self.wclk, 100)
            await self._wait_read_done()

            # 8- precisely test almost empty
            self.dut._log.debug('*** %6s TEST 8 ***' % self.name)
            self.dut.test_phase.value = self.harness.hexstring("%6s phase 8" % self.name)
            await self._do_writes(0, self.dut_almost_empty, self.rclk, [1, 1, 0])
            await ClockCycles(self.wclk, 100)
            await self._wait_read_done()

            ## x- test overflow / underflow(?)

    async def _wait_read_done(self) -> None:
            while not self.read_done:
                await ClockCycles(self.rclk, 1)
            if not self.sync:
                await ClockCycles(self.rclk, 10) # generous margin for CDC

    async def _do_writes(self, target_fill, watch_flag=None, watch_clock=None, watch_values=[]) -> None:
        """ Starting from an empty FIFO, fills it to target_fill, then
        allow reads to start.
        """
        assert self.empty
        assert self.almost_empty
        assert self._reads_allowed.empty()
        await self._write(target_fill)
        if watch_flag:
            for i in range(len(watch_values)):
                await ClockCycles(watch_clock, 10)
                #self.dut.test_phase.value = self.harness.hexstring("bit %d" % i)
                if watch_flag.value != watch_values[i]:
                    self.harness.inc_error()
                    self.dut._log.error("%6s Wrong flag value on iteration %d" % (self.name, i))
                await self._write(1)
            extra_rw = 0
        else:
            # do some extra r/w around the point of interest; randomized so that the FIFO pointers don't
            # always end up at the same spot:
            extra_rw = random.randint(100,200)

        self._reads_allowed.put_nowait(target_fill+extra_rw+len(watch_values))
        await self._write(extra_rw)

    async def _write(self, num) -> None:
        """ Execute num writes.
        """
        if num == 0:
            return
        writes_done = 0
        await ClockCycles(self.wclk, 1)
        while writes_done < num:
            writes = random.randint(self.min_burst, self.max_burst)
            if writes + writes_done >= num:
                writes = num - writes_done
            for _ in range(writes):
                while (self.full or (self.almost_full and self.dut_write.value)):
                #while self.full:
                    self.dut._log.debug("%6s waiting to write... full=%d, almost_full=%d" % (self.name, self.full, self.almost_full))
                    self.dut_write.value = 0
                    await ClockCycles(self.wclk, 1)
                self.dut._log.debug("%6s good to write! full=%d, almost_full=%d" % (self.name, self.full, self.almost_full))
                self.dut_write.value = 1
                wdata = random.randint(0, 2**16-1)
                self.dut_wdata.value = wdata
                self._fifo_data_queue.put_nowait(wdata)
                self.adjust_fill_state(+1)
                await ClockCycles(self.wclk, 1)
                writes_done += 1
                if writes_done == num:
                    break
            self.dut_write.value = 0
            await ClockCycles(self.wclk, random.randint(self.min_idle, self.max_idle))

    async def _read_thread(self) -> None:
        self.dut._log.debug('%6s _read_thread starting' % self.name)
        while True:
            reads_to_do = await self._reads_allowed.get()
            await ClockCycles(self.rclk, 1)
            self.dut._log.debug("_read_thread: %d reads to do" % reads_to_do)
            self.read_done = False
            reads_done = 0
            while reads_done < reads_to_do:
                await self.wait_signal(self.dut_empty, 0, self.rclk)
                reads = random.randint(self.min_burst, self.max_burst)
                for _ in range(reads):
                    while (self.empty or (self.almost_empty and self.dut_read.value)):
                        self.dut_read.value = 0
                        await ClockCycles(self.rclk, 1)
                    self.dut_read.value = 1
                    self.adjust_fill_state(-1)
                    await ClockCycles(self.rclk, 1)
                    reads_done += 1
                    if reads_done == reads_to_do:
                        break
                self.dut_read.value = 0
                await ClockCycles(self.rclk, random.randint(self.min_idle, self.max_idle))
            self.read_done = True

    async def _check_thread(self) -> None:
        """ This is done outside of _read_thread to more easily accomodate
        first-word-fall-through vs "normal" configurations.
        """
        self.dut._log.debug('%6s _check_thread starting' % self.name)
        while True:
            await self.wait_signal(self.dut_read, 1, self.rclk)
            if self.fwft:
                rdata = self.dut_rdata.value
                await ClockCycles(self.rclk, 1)
            else:
                await ClockCycles(self.rclk, 1)
                rdata = self.dut_rdata.value
            edata = self._fifo_data_queue.get_nowait()
            if rdata != edata:
                self.harness.inc_error()
                self.dut._log.error("%6s Expected %4x, got %4x" % (self.name, edata, rdata))
            else:
                self.dut._log.debug("%6s Expected %4x, got %4x" % (self.name, edata, rdata))

    async def _over_thread(self) -> None:
        """ Checks for overflow and other write-side flags.
        """
        self.dut._log.debug('%6s _over_thread starting' % self.name)
        await RisingEdge(self.dut.rst_n)
        await ClockCycles(self.wclk, 5)
        while True:
            if self.dut_overflow.value:
                self.harness.inc_error()
                self.dut._log.error("%6s overflow!" % self.name)

            # loose checks on programmable full threshold:
            if self.dut_full_threshold.value == 0:
                if self.actual_fill_state > self.full_threshold + self.fill_state_slop:
                    self.harness.inc_error()
                    self.dut._log.error("%6s missing full threshold flag! (actual fill state: %d; programmed threshold: %d)" % (self.name, self.actual_fill_state, self.full_threshold))
            else: # dut_full_threshold = 1
                if self.actual_fill_state < self.full_threshold - self.fill_state_slop:
                    self.harness.inc_error()
                    self.dut._log.error("%6s unexpected full threshold flag! (actual fill state: %d; programmed threshold: %d)" % (self.name, self.actual_fill_state, self.full_threshold))

            # even looser checks on almost/full:
            if self.full:
                if self.actual_fill_state < self.depth - self.fill_state_slop:
                    self.harness.inc_error()
                    self.dut._log.error("%6s unexpected full flag! (actual fill state: %d; depth: %d)" % (self.name, self.actual_fill_state, self.depth))
            if self.almost_full:
                if self.actual_fill_state < self.depth - 1 - self.fill_state_slop:
                    self.harness.inc_error()
                    self.dut._log.error("%6s unexpected almost full flag! (actual fill state: %d; depth: %d)" % (self.name, self.actual_fill_state, self.depth))

            await ClockCycles(self.wclk, 1)

    async def _under_thread(self) -> None:
        """ Checks for underflow and other read-side flags.
        """
        self.dut._log.debug('%6s _under_thread starting' % self.name)
        await RisingEdge(self.dut.rst_n)
        await ClockCycles(self.rclk, 5)
        while True:
            if self.dut_underflow.value:
                self.harness.inc_error()
                self.dut._log.error("%6s underflow!" % self.name)

            # loose checks on programmable empty threshold:
            if self.dut_empty_threshold.value == 0:
                if self.actual_fill_state < self.empty_threshold - self.fill_state_slop:
                    self.harness.inc_error()
                    self.dut._log.error("%6s missing empty threshold flag! (actual fill state: %d; programmed threshold: %d)" % (self.name, self.actual_fill_state, self.empty_threshold))
            else: # dut_empty_threshold = 1
                if self.actual_fill_state > self.empty_threshold + self.fill_state_slop + 1:
                    self.harness.inc_error()
                    self.dut._log.error("%6s unexpected empty threshold flag! (actual fill state: %d; programmed threshold: %d)" % (self.name, self.actual_fill_state, self.empty_threshold))

            # even looser checks on almost/empty:
            if self.empty:
                if self.actual_fill_state > 1 + self.fill_state_slop:
                    self.harness.inc_error()
                    self.dut._log.error("%6s unexpected empty flag! (actual fill state: %d)" % (self.name, self.actual_fill_state))
            if self.almost_empty:
                if self.actual_fill_state > 2 + self.fill_state_slop:
                    self.harness.inc_error()
                    self.dut._log.error("%6s unexpected almost empty flag! (actual fill state: %d)" % (self.name, self.actual_fill_state))

            await ClockCycles(self.rclk, 1)

    @property
    def full(self):
        return self.dut_full.value

    @property
    def almost_full(self):
        return self.dut_almost_full.value

    @property
    def empty(self):
        return self.dut_empty.value

    @property
    def almost_empty(self):
        return self.dut_almost_empty.value

    #@staticmethod - hmm, looks like staticmethod + async don't play well together?
    async def wait_signal(self, signal, value, clock):
        while signal != value:
            await ClockCycles(clock, 1)

    def adjust_fill_state(self, val):
        self.actual_fill_state += val
        self.dut.actual_fill_state.value = self.actual_fill_state



@cocotb.test(timeout_time=1500, timeout_unit="us")
#@cocotb.test(skip=True)
async def fifo_test(dut):
    reps  = int(os.getenv('REPS', '2'))

    full_threshold = int(os.getenv('FTHRESH', '0'))
    empty_threshold = int(os.getenv('ETHRESH', '0'))
    depth = dut.pDEPTH.value
    if full_threshold == 0:
        full_threshold = random.randint(2,depth-2)
    if empty_threshold == 0:
        empty_threshold = random.randint(2,depth-2)
    dut._log.info("FIFO depth: %d" % depth)
    dut._log.info("Programmable full threshold: %d" % full_threshold)
    dut._log.info("Programmable empty threshold: %d" % empty_threshold)

    dut._log.info("FLOPs: %d" % dut.pFLOPS.value)
    dut._log.info("BRAM: %d" % dut.pBRAM.value)
    dut._log.info("DISTRIBUTED: %d" % dut.pDISTRIBUTED.value)
    dut._log.info("FWFT: %d" % dut.pFWFT.value)
    dut._log.info("SYNC: %d" % dut.pSYNC.value)

    harness = Harness(dut, reps, full_threshold, empty_threshold)
    await harness.reset()

    if int(os.getenv('FIFOTEST')):
        synctest = FifoTest(dut, harness, "sync_normal",
                            fwft = dut.pFWFT.value,
                            sync = dut.pSYNC.value,
                            depth = depth,
                            full_threshold = full_threshold,
                            empty_threshold = empty_threshold,
                            dut_full = dut.full,
                            dut_empty = dut.empty,
                            dut_almost_full = dut.almost_full,
                            dut_almost_empty = dut.almost_empty,
                            dut_write = dut.wen,
                            dut_wdata = dut.wdata,
                            dut_read = dut.ren,
                            dut_rdata = dut.rdata,
                            dut_overflow = dut.overflow,
                            dut_underflow = dut.underflow,
                            dut_full_threshold = dut.full_threshold,
                            dut_empty_threshold = dut.empty_threshold)
        harness.register_test(synctest)


    harness.start_tests()
    await harness.all_tests_done()
    assert harness.errors == 0



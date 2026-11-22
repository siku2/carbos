#!/usr/bin/env python3
"""Plot to a Fenta cutter in HP-GL.

The firmware acts on IN; as soon as it arrives and drops the moves that are
still queued, so the job must not end with it. SP0; ends the job and feeds
the material past the drawing.
"""

import inkex
from inkex.ports import Serial

import plotter


class FentaPlot(plotter.Plot):
    def add_arguments(self, pars):
        super().add_arguments(pars)
        pars.add_argument("--feed", type=inkex.Boolean, default=True)

    def convert_hpgl(self, hpgl):
        end = ";PU0,0;SP0;" if self.options.feed else ";PU0,0;"
        return "IN" + hpgl + end

    def to_serial(self, hpgl):
        with Serial(
            self.options.serialPort,
            baud=self.options.serialBaudRate,
            stop="one",
            size="eight",
            flow="rtscts",
            parity="none",
        ) as com:
            com.write(hpgl.encode())
            # Wait for the whole job. Closing early lets the kernel drop the
            # rest after its closing timeout.
            com.flush()


if __name__ == "__main__":
    FentaPlot().run()

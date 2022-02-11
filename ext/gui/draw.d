// module purr.gui.z3d;

// import gtk.Widget;
// import gtk.DrawingArea;
// import cairo.Context;

// class DrawArea : DrawingArea {
//     Dynamic obj = Dynamic.nil;

//     this() {
//         super();
//         addOnDraw(&draw);
//     }

//     bool draw(Scoped!Context context, Widget w) {
//         context.setSourceRgb(0, 0, 0);
//         context.fill();
//         context.setSourceRgb(0.5, 0.5, 0.5);
//         context.setLineWidth(3);
//         context.moveTo(0, 0);
//         context.lineTo(100, 100);
//         context.stroke();
//         return true;
//     }
// }

module purr.gui.draw;

import gtk.Widget;
import gtk.DrawingArea;
import cairo.Context;

import purr.dynamic;

import std.array;
import std.math;
import std.algorithm;


class Draw {
    Dynamic[] drawn;
    Context ctx;
    int[2] size;

    this(Context ctx_, int xsize, int ysize)
    {
        size = [xsize, ysize];
        ctx = ctx_;
    }

    void draw(Dynamic val)
    {
        foreach (ent; drawn)
        {
            if (ent is val)
            {
                return;
            }
        }
        drawn ~= val;
        if (val.isArray)
        {
            foreach (ent; val.arr)
            {
                draw(ent);
            }
        }
        else if (val.isTable)
        {
            Dynamic dyn = val.tab.get("color".dynamic, Dynamic.nil);
            double[3] color = [0, 0, 0];
            if (dyn.isArray && dyn.arr.length == 3)
            {
                color = dyn.arr.map!(x => x.num / 256).array[0 .. 3];
            }
            Dynamic th = val.tab.get("width".dynamic, Dynamic.nil);
            double thick = 1;
            if (th.isNumber)
            {
                thick = th.num;
            }
            Dynamic line = val.tab.get("line".dynamic, Dynamic.nil);
            if (line.isArray && line.arr.length == 4)
            {
                ctx.setSourceRgb(color[0], color[1], color[2]);
                ctx.setLineWidth(thick);
                double[4] values = line.arr.map!(x => x.num).array;
                ctx.moveTo(values[0], values[1]);
                ctx.lineTo(values[2], values[3]);
                if (values[0] > values[2])
                {
                    swap(values[0], values[2]);
                }
                if (values[1] > values[3])
                {
                    swap(values[1], values[3]);
                }
                val.tab.set("line".dynamic, values[0..4].map!(x => x.dynamic).array.dynamic);
                ctx.stroke();
            }
        }
    }
}

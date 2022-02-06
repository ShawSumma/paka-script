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
import std.algorithm;

Dynamic[] above;

void draw(Context ctx, Dynamic val)
{
    foreach (ent; above)
    {
        if (ent is val)
        {
            return;
        }
    }
    above ~= val;
    scope (exit)
        above.length -= 1;
    if (val.isArray)
    {
        foreach (ent; val.arr)
        {
            draw(ctx, ent);
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
            ctx.moveTo(line.arr[0].num, line.arr[1].num);
            ctx.lineTo(line.arr[2].num, line.arr[3].num);
            ctx.stroke();
        }
    }
}

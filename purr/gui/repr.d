module purr.gui.repr;

import std.algorithm;
import std.conv;
import std.range;

import purr.dynamic;
import purr.bytecode;

import gtk.Box;
import gtk.Grid;
import gtk.Widget;
import gtk.Label;
import gtk.Expander;

enum marginStart = 10;

private Widget text(string src)
{
    Label ret = new Label(src);
    ret.setAlignment(0, 0);
    return ret;
}

Widget tableToWidget(Table tab)
{
    Grid grid = new Grid();
    grid.setMarginStart(marginStart);
    int count = 0;
    Dynamic[] keys;
    foreach (key, value; tab)
    {
        keys ~= key;
    }
    keys.sort;
    foreach (key; keys)
    {
        Dynamic value = tab.get(key, Dynamic.nil);
        Widget wkey = key.dynamicToWidget;
        Widget wvalue = value.dynamicToWidget;
        grid.attach(wkey, 0, count, 1, 1);
        grid.attach(wvalue, 1, count, 1, 1);
        count += 1;
    }
    // foreach (key, value; tab)
    // {
    //     if (!key.isArray && !key.isTable && !value.isTable)
    //     {
    //         box.add(value.dynamicToWidget);
    //     }
    // }
    // foreach (key, value; tab)
    // {
    //     if (key.isArray || key.isTable)
    //     {
    //         Expander ent;
    //         if (key.isArray)
    //         {
    //             ent = new Expander("[...]");
    //         }
    //         else
    //         {
    //             ent = new Expander("{...}");
    //         }
    //         Box pair = new Box(Orientation.HORIZONTAL, 0);
    //         pair.setMarginStart(marginStart);
    //         pair.add(key.dynamicToWidget);
    //         pair.add(value.dynamicToWidget);
    //         ent.add(pair);
    //         box.add(ent);
    //     }
    // }
    return grid;
}

Box bytecodeToBox(Bytecode bc)
{
    Box box = new Box(Orientation.VERTICAL, 0);
    {
        Expander cap = new Expander("closure");
        cap.setMarginStart(marginStart);
        bool added = false;
        cap.addOnActivate((Expander e) {
            if (added)
            {
                return;
            }
            foreach (ind, captured; bc.captured)
            {
                Expander ex = new Expander(bc.captab[ind]);
                ex.setMarginStart(marginStart);
                ex.add((*captured).dynamicToWidget);
                cap.add(ex);
            }
            cap.showAll();
            added = true;
        });
        box.add(cap);
    }
    {
        Expander bytecode = new Expander("bytecode");
        bytecode.setMarginStart(marginStart);
        bool added = false;
        bytecode.addOnActivate((Expander e) {
            if (added)
            {
                return;
            }
            ubyte[] bytes = bc.instrs;
            ubyte[][] chunks = bytes.chunks(16).array;
            string next;
            foreach (index, chunk; chunks)
            {
                if (index != 0)
                {
                    next ~= '\n';
                }
                foreach (entno, ent; chunk)
                {
                    if (entno != 0)
                    {
                        next ~= ' ';
                    }
                    next ~= (ent % 0x10).to!string(16);
                    next ~= (ent / 0x10 % 0x10).to!string(16);
                }
            }
            Widget view = text(next);
            view.setMarginStart(marginStart);
            bytecode.add(view);
            bytecode.showAll();
            added = true;
        });
        box.add(bytecode);
    }
    {
        Expander cap = new Expander("constants");
        cap.setMarginStart(marginStart);
        bool added = false;
        cap.addOnActivate((Expander e) {
            if (added)
            {
                return;
            }
            Box box = new Box(Orientation.VERTICAL, 0);
            foreach (ind, constant; bc.constants)
            {
                box.add(constant.dynamicToWidget);
            }
            cap.add(box);
            cap.showAll();
            added = true;
        });
        box.add(cap);
    }
    return box;
}

Widget dynamicToWidget(Dynamic dyn)
{
    final switch (dyn.type)
    {
    case Dynamic.Type.nil:
    case Dynamic.Type.log:
    case Dynamic.Type.sml:
    case Dynamic.Type.sym:
    case Dynamic.Type.tup:
        Widget ret = text(dyn.to!string);
        ret.setMarginStart(marginStart);
        return ret;
    case Dynamic.Type.str:
        Widget ret = text(dyn.str);
        ret.setMarginStart(marginStart);
        return ret;
    case Dynamic.Type.arr:
        string arrayRepr;
        if (dyn.arr.length == 0)
        {
            arrayRepr = "[]";
        }
        else
        {
            arrayRepr = "[...]";
        }
        Expander ret = new Expander(arrayRepr);
        ret.setMarginStart(marginStart);
        bool added = false;
        ret.addOnActivate((Expander e) {
            if (added)
            {
                return;
            }
            Box box = new Box(Orientation.VERTICAL, 0);
            foreach (ent; dyn.arr)
            {
                box.add(ent.dynamicToWidget);
            }
            e.add(box);
            e.showAll();
            added = true;
        });
        return ret;
    case Dynamic.Type.tab:
        string tableRepr;
        if (dyn.tab.length == 0)
        {
            tableRepr = "table {}";
        }
        else
        {
            tableRepr = "table {...}";
        }
        Expander ret = new Expander(tableRepr);
        ret.setMarginStart(marginStart);
        bool added = false;
        ret.addOnActivate((Expander e) {
            if (added)
            {
                return;
            }
            e.add(dyn.tab.tableToWidget);
            e.showAll();
            added = true;
        });
        return ret;
    case Dynamic.Type.fun:
        Widget ret = text("lambda {}");
        ret.setMarginStart(marginStart);
        return ret;
    case Dynamic.Type.pro:
        Expander ret = new Expander("lambda {...}");
        ret.setMarginStart(marginStart);
        Box box = dyn.value.fun.pro.bytecodeToBox;
        ret.add(box);
        return ret;
    }
}

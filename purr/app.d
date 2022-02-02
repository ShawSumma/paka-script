module purr.app;

import purr.io;
import purr.repl;
import purr.ir.repr;
import purr.ir.opt;
import purr.ir.walk;
import purr.vm;
import purr.bugs;
import purr.srcloc;
import purr.base;
import purr.ast.ast;
import purr.dynamic;
import purr.parse;
import purr.inter;
import purr.io;
import purr.serial.fromjson;
import purr.serial.tojson;
import purr.fs.files;
import purr.fs.disk;
import purr.bytecode;
import purr.ir.walk;

import std.uuid;
import std.path;
import std.array;
import std.file;
import std.json;
import std.range;
import std.ascii;
import std.algorithm;
import std.process;
import std.conv;
import std.string;
import std.getopt;
import std.datetime.stopwatch;
import core.memory;
import core.time;

import gtk.Main;
import gtk.MainWindow;
import gtk.Box;
import gtk.Entry;
import gtk.Widget;
import gtk.Button;
import gtk.TextView;
import gtk.TextBuffer;
import gtk.ListBox;
import gtk.CssProvider;
import gtk.ScrolledWindow;
import gtk.Paned;
import gtk.Expander;
import gtk.Grid;

import gdk.Event;

__gshared size_t ctx = size_t.max;

void thrown(Err)(Err e)
{
    size_t[] nums;
    size_t[] times;
    string[] files;
    size_t ml = 0;
    foreach (df; debugFrames)
    {
        Span span = df.span;
        if (nums.length != 0 && nums[$ - 1] == span.first.line)
        {
            times[$ - 1]++;
        }
        else
        {
            nums ~= span.first.line;
            files ~= span.first.file;
            times ~= 1;
            ml = max(ml, span.first.line.to!string.length);
        }
    }
    string trace;
    string last = "__main__";
    foreach (i, v; nums)
    {
        if (i == 0)
        {
            trace ~= "on line ";
        }
        else
        {
            trace ~= "from line ";
        }
        foreach (j; 0 .. ml - v.to!string.length)
        {
            trace ~= " ";
        }
        trace ~= v.to!string;
        if (files[i] != last)
        {
            last = files[i];
            trace ~= " (file: " ~ last ~ ")";
        }
        if (times[i] > 2)
        {
            trace ~= " (repeated: " ~ times[i].to!string ~ " times)";
        }
        trace ~= "\n";
    }
    debugFrames.length = 0;
    writeln(trace);
    writeln(e.msg);
    writeln;
}

void setMarginAll(Widget widget, int size)
{
    widget.setMarginTop(size);
    widget.setMarginBottom(size);
    widget.setMarginLeft(size);
    widget.setMarginRight(size);
}

TextView text(string src)
{
    TextView ret = new TextView();
    ret.setMonospace(true);
    ret.setEditable(false);
    ret.getBuffer().setText(src);
    return ret;
}

Box tableToBox(Table tab)
{
    Box box = new Box(Orientation.VERTICAL, 0);
    box.setMarginStart(16);
    foreach (key, value; tab)
    {
        if (!key.isArray && !key.isTable)
        {
            string name;
            if (key.isString)
            {
                name = key.str;
            }
            else
            {
                name = key.to!string;
            }
            Expander ent = new Expander(name);
            ent.add(value.dynamicToWidget);
            box.add(ent);
        }
    }
    foreach (key, value; tab)
    {
        if (key.isArray || key.isTable)
        {
            Expander ent;
            if (key.isArray)
            {
                ent = new Expander("[...]");
            }
            else
            {
                ent = new Expander("{...}");
            }
            Box pair = new Box(Orientation.HORIZONTAL, 0);
            pair.setMarginStart(16);
            pair.add(key.dynamicToWidget);
            pair.add(value.dynamicToWidget);
            ent.add(pair);
            box.add(ent);
        }
    }
    return box;
}

Box bytecodeToBox(Bytecode bc)
{
    Box box = new Box(Orientation.VERTICAL, 0);
    {
        Expander cap = new Expander("closure");
        cap.setMarginStart(16);
        bool added = false;
        cap.addOnActivate((Expander e) {
            if (added)
            {
                return;
            }
            foreach (ind, captured; bc.captured)
            {
                Expander ex = new Expander(bc.captab[ind]);
                ex.setMarginStart(16);
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
        bytecode.setMarginStart(16);
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
            TextView view = text(next);
            view.setMarginStart(16);
            bytecode.add(view);
            bytecode.showAll();
            added = true;
        });
        box.add(bytecode);
    }
    {
        Expander cap = new Expander("constants");
        cap.setMarginStart(16);
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
    case Dynamic.Type.str:
    case Dynamic.Type.tup:
        TextView ret = text(dyn.to!string);
        ret.setMarginStart(16);
        ret.setHscrollPolicy(ScrollablePolicy.MINIMUM);
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
        ret.setMarginStart(16);
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
        ret.setMarginStart(16);
        bool added = false;
        ret.addOnActivate((Expander e) {
            if (added)
            {
                return;
            }
            e.add(dyn.tab.tableToBox);
            e.showAll();
            added = true;
        });
        return ret;
    case Dynamic.Type.fun:
        TextView ret = text("lambda {}");
        ret.setMarginStart(16);
        ret.setHscrollPolicy(ScrollablePolicy.MINIMUM);
        return ret;
    case Dynamic.Type.pro:
        Expander ret = new Expander("lambda {...}");
        ret.setMarginStart(16);
        Box box = dyn.value.fun.pro.bytecodeToBox;
        ret.add(box);
        return ret;
    }
}

void main(string[] args)
{
    ctx = enterCtx;
    scope (exit)
        exitCtx;
    string[] names;
    foreach (ent; rootBases[ctx])
    {
        names ~= ent.name;
    }
    string outdir = ".repl";
    string saveFileName = outdir ~ "/save.json";
    string textStringFileName = outdir ~ "/term.txt";
    string textString;
    {
        if (textStringFileName.exists && textStringFileName.isFile)
        {
            textString = textStringFileName.readText;
        }
        if (saveFileName.exists && saveFileName.isFile)
        {
            rootBases[ctx] = saveFileName.readText.parseJSON.deserialize!(Pair[]);
        }
    }
    scope (exit)
    {
        if (outdir.exists && outdir.isFile)
        {
            outdir.remove;
        }
        if (!outdir.exists)
        {
            outdir.mkdir;
        }
        std.file.write(saveFileName, rootBases[ctx].serialize);
        std.file.write(textStringFileName, textString);
    }
    Main.init(args);
    MainWindow mainWindow = new MainWindow("Paka");
    {
        Grid mainGrid = new Grid();
        mainGrid.setHexpand(true);
        mainGrid.setVexpand(true);
        Box dataBox = new Box(Orientation.VERTICAL, 0);
        TextView textView = new TextView();
        textView.setMonospace(true);
        textView.setWrapMode(WrapMode.CHAR);
        textView.setEditable(false);
        dataBox.add(textView);
        mainGrid.attach(dataBox, 0, 7, 8, 1);
        {
            Box inputBox = new Box(Orientation.HORIZONTAL, 0);
            Box output = new Box(Orientation.VERTICAL, 0);
            Box globals = new Box(Orientation.VERTICAL, 0);
            {
                void loadAllGlobals()
                {
                    Table builtinTable = new Table();
                    Table globalTable = new Table();
                    Table hiddenTabele = new Table();
                    foreach (ent; rootBases[ctx])
                    {
                        if (ent.name.startsWith("_"))
                        {
                            hiddenTabele.set(ent.name.dynamic, ent.val);
                        }
                        else if (names.canFind(ent.name))
                        {
                            builtinTable.set(ent.name.dynamic, ent.val);
                        }
                        else
                        {
                            globalTable.set(ent.name.dynamic, ent.val);
                        }
                    }
                    globals.removeAll();
                    {
                        Box box = globalTable.tableToBox;
                        Expander exp = new Expander("globals");
                        exp.setExpanded(true);
                        exp.add(box);
                        globals.add(exp);
                    }
                    {
                        Box box = builtinTable.tableToBox;
                        Expander exp = new Expander("builtins");
                        exp.add(box);
                        globals.add(exp);
                    }
                    {
                        Box box = hiddenTabele.tableToBox;
                        Expander exp = new Expander("hidden");
                        exp.add(box);
                        globals.add(exp);
                    }
                    globals.showAll();
                }

                bool runAll(string text)
                {
                    textString = null;
                    void delegate(char) last = write1c;
                    scope (exit)
                        write1c = last;
                    write1c = (char c) {
                        TextBuffer buf = textView.getBuffer();
                        textString ~= c;
                        buf.setText(textString);
                    };
                    Dynamic res = Dynamic.nil;
                    try
                    {
                        res = ctx.eval(SrcLoc(1, 1, "__input__", text));
                    }
                    catch (Error e)
                    {
                        e.thrown;
                        return false;
                    }
                    catch (Exception e)
                    {
                        e.thrown;
                        return false;
                    }
                    loadAllGlobals();
                    output.removeAll();
                    output.add(res.dynamicToWidget);
                    output.showAll();
                    return true;
                }

                loadAllGlobals();

                Entry textInput = new Entry();
                Button runInput = new Button("RUN!");
                textInput.addOnActivate((Entry ent) {
                    if (runAll(textInput.getText()))
                    {
                        textInput.setText("");
                    }
                });
                runInput.addOnClicked((Button button) {
                    if (runAll(textInput.getText()))
                    {
                        textInput.setText("");
                    }
                });
                inputBox.packStart(textInput, true, true, 0);
                inputBox.packEnd(runInput, false, false, 0);
            }
            inputBox.setHexpand(true);
            mainGrid.attach(inputBox, 0, 0, 8, 1);
            mainGrid.attach(output, 4, 1, 4, 6);
            mainGrid.attach(globals, 0, 1, 4, 6);
        }
        Box mainBox = new Box(Orientation.VERTICAL, 0);
        // mainBox.packStart(mainGrid, false, false, 0);
        mainBox.packStart(mainGrid, false, true, 0);
        // mainBox.packStart(mainGrid, false, true, 0);
        // mainBox.packStart(mainGrid, true, true, 0);
        mainWindow.add(mainBox);
    }
    mainWindow.showAll();
    Main.run();

    // ctx.eval(src);
    // string file = args[1];
    // string src = file.readText;    

}

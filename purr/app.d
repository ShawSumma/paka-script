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
    ret.setRightMargin(8);
    ret.setMonospace(true);
    ret.setEditable(false);
    ret.getBuffer().setText(src);
    return ret;
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
    case Dynamic.Type.fun:
    case Dynamic.Type.pro:
    case Dynamic.Type.tup:
        TextView ret = text(dyn.to!string);
        ret.setMarginLeft(16);
        ret.setHscrollPolicy(ScrollablePolicy.MINIMUM);
        return ret;
    case Dynamic.Type.arr:
        ListBox ret = new ListBox();
        ret.setMarginLeft(16);
        ret.add(text("[...]"));
        foreach (ent; dyn.arr)
        {
            ret.add(ent.dynamicToWidget);
        }
        return ret;
    case Dynamic.Type.tab:
        ListBox ret = new ListBox();
        ret.setMarginLeft(16);
        ret.add(text("table {...}"));
        foreach (key, value; dyn.tab)
        {
            Box pair = new Box(Orientation.HORIZONTAL, 0);
            pair.add(key.dynamicToWidget);
            pair.add(text(":"));
            pair.add(value.dynamicToWidget);
            ret.add(pair);
        }
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
    Main.init(args);
    MainWindow window = new MainWindow("Paka");
    ScrolledWindow mainWindow = new ScrolledWindow();
    window.add(mainWindow);
    {
        Box mainBox = new Box(Orientation.VERTICAL, 0);
        string textString;
        {
            Box dataBox = new Box(Orientation.VERTICAL, 0);
            {
                TextView textView = new TextView();
                textView.setMonospace(true);
                textView.setWrapMode(WrapMode.CHAR);
                textView.setEditable(false);
                write1c = (char c) {
                    TextBuffer buf = textView.getBuffer();
                    textString ~= c;
                    buf.setText(textString);
                };
                dataBox.add(textView);
            }
            mainBox.add(dataBox);
        }
        {
            Box inputBox = new Box(Orientation.HORIZONTAL, 0);
            Box host = new Box(Orientation.VERTICAL, 0);
            {

                void setOutput(Args...)(Args args)
                {
                    Paned done = new Paned(Orientation.HORIZONTAL);
                    Dynamic[string] values;
                    foreach (ent; rootBases[ctx])
                    {
                        if (!ent.name.startsWith("_") && !names.canFind(ent.name))
                        {
                            values[ent.name] = ent.val;
                        }
                    }
                    Box next = new Box(Orientation.VERTICAL, 0);
                    foreach (name; values.keys.sort)
                    {
                        Box cur = new Box(Orientation.HORIZONTAL, 0);
                        cur.add(text(name));
                        cur.add(text(":"));
                        cur.add(values[name].dynamicToWidget);
                        next.add(cur);
                    }
                    done.pack2(next, true, true);
                    Box first = new Box(Orientation.VERTICAL, 0);
                    static foreach (arg; args)
                    {
                        first.add(arg);
                    }
                    done.pack1(first, true, true);
                    host.removeAll();
                    host.add(done);
                    mainWindow.showAll();
                }

                setOutput(text(""));

                Entry textInput = new Entry();
                Button runInput = new Button("RUN!");
                runInput.addOnClicked((Button button) {
                    textString = null;
                    string text = textInput.getText();
                    Dynamic res = Dynamic.nil;
                    try
                    {
                        res = ctx.eval(SrcLoc(1, 1, "__input__", text));
                    }
                    catch (Error e)
                    {
                        e.thrown;
                    }
                    catch (Exception e)
                    {
                        e.thrown;
                    }
                    setOutput(res.dynamicToWidget);
                });
                inputBox.add(runInput);
                inputBox.add(textInput);
            }
            mainBox.add(inputBox);
            mainBox.add(host);
        }
        mainWindow.add(mainBox);
    }
    window.showAll();
    Main.run();

    // ctx.eval(src);
    // string file = args[1];
    // string src = file.readText;    

}

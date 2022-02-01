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

void setMarginAll(Widget widget, int size) {
    widget.setMarginTop(size);
    widget.setMarginBottom(size);
    widget.setMarginLeft(size);
    widget.setMarginRight(size);
}

TextView text(string src) {
    TextView ret = new TextView();
    ret.setMonospace(true);
    ret.setEditable(false);
    ret.getBuffer().setText(" " ~ src ~ " ");
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
        foreach (ent; dyn.arr) {
            ret.add(ent.dynamicToWidget);
        }
        return ret;
    case Dynamic.Type.tab:
        ListBox ret = new ListBox();
        ret.setMarginLeft(16);
        ret.add(text("table {...}"));
        foreach (key, value; dyn.tab) {
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
    Main.init(args);
    MainWindow mainWindow = new MainWindow("Paka");
    {
        Box mainBox = new Box(Orientation.VERTICAL, 0);
        string textString;
        {
            Box inputBox = new Box(Orientation.HORIZONTAL, 0);
            {
                Widget repr = new Box(Orientation.VERTICAL, 0);
                Entry textInput = new Entry();
                Button runInput = new Button("RUN!");
                runInput.addOnClicked((Button button) {
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
                    mainBox.remove(repr);
                    repr = res.dynamicToWidget;
                    mainBox.add(repr);
                    mainBox.showAll();
                });
                inputBox.add(runInput);
                inputBox.add(textInput);
            }
            mainBox.add(inputBox);
        }
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
        mainWindow.add(mainBox);
    }
    mainWindow.showAll();
    Main.run();

    // ctx.eval(src);
    // string file = args[1];
    // string src = file.readText;    

}

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
import gtk.Label;
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
import gtk.Frame;

import gdk.Event;

import purr.gui.repr;

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
    mainWindow.setDefaultSize(800, 450);
    {
        Box dataBox = new Box(Orientation.VERTICAL, 0);
        Label label = new Label("");
        dataBox.add(label);
        Box mainBox = new Box(Orientation.VERTICAL, 0);
        {
            Box inputBox = new Box(Orientation.HORIZONTAL, 0);
            Box output = new Box(Orientation.VERTICAL, 0);
            ScrolledWindow globalsScrollable = new ScrolledWindow();
            {
                Box globals = new Box(Orientation.VERTICAL, 0);
                globalsScrollable.add(globals);
                
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
                        Widget box = globalTable.tableToWidget;
                        Expander exp = new Expander("globals");
                        exp.setExpanded(true);
                        exp.add(box);
                        globals.add(exp);
                    }
                    {
                        Widget box = builtinTable.tableToWidget;
                        Expander exp = new Expander("builtins");
                        exp.add(box);
                        globals.add(exp);
                    }
                    {
                        Widget box = hiddenTabele.tableToWidget;
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
                        stdout.write(c);
                        textString ~= c;
                        label.setLabel(textString);
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
            Box box = new Box(Orientation.HORIZONTAL, 0);
            box.add(output);
            box.add(globalsScrollable);
            box.setHomogeneous(true);
            mainBox.packStart(box, true, true, 0);
            mainBox.packEnd(inputBox, false, false, 0);
            mainBox.packEnd(dataBox, false, false, 0);
        }
        mainWindow.add(mainBox);
    }
    mainWindow.showAll();
    Main.run();

}

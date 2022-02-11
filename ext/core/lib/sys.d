module ext.core.lib.sys;

import purr.io;
import purr.dynamic;
import purr.base;
import purr.ast.ast;
import purr.parse;
import purr.ir.walk;
import purr.vm;
import purr.inter;
import purr.srcloc;
import purr.bytecode;
import purr.fs.memory;
import purr.fs.har;
import purr.fs.files;
import purr.fs.disk;
import purr.ctx;
import ext.core.lib.sysenv;
import core.stdc.stdlib;
import core.runtime;
import std.algorithm;
import std.file;
import std.path;
import std.array;
import std.process;
import std.conv;
import std.parallelism;

Pair[] libsys()
{
    Pair[] ret = [
        FunctionPair!libleave("leave"), FunctionPair!libargs("args"),
        FunctionPair!libimport("import"),
        FunctionPair!libassert("enforce"), FunctionPair!libeval("eval"),
    ];
    ret.addLib("env", libsysenv);
    return ret;
}

/// asserts value is true, with error msg
Dynamic libassert(Args args)
{
    if (!args[0].isTruthy)
    {
        throw new Exception("assert error: " ~ args[1].to!string);
    }
    return Dynamic.nil;
}

/// imports value returning what it returned
Dynamic libimport(Args args) {
    Context ctx = Context.base;
    string cdir = getcwd;
    scope (exit)
    {
        cdir.chdir;
    }
    string filename = args[0].str;
    filename.dirName.chdir;
    SrcLoc data = filename.readFile;
    Dynamic val = ctx.eval(data);
    return val;
}

/// imports value returning what it returned
Dynamic libeval(Args args)
{
    Context ctx = Context.base;
    SrcLoc data = SrcLoc(1, 1, "__eval__", args[0].str);
    Dynamic val = eval(ctx, data);
    return val;
}

/// internal map function
Dynamic syslibmap(Args args)
{
    Array ret;
    foreach (i; 0 .. args[1].arr.length)
    {
        Array fargs;
        foreach (j; args[1 .. $])
        {
            fargs ~= j.arr[i];
        }
        ret ~= args[0](fargs);
    }
    return dynamic(ret);
}
/// exit function
Dynamic libleave(Args args)
{
    exit(0);
    assert(0);
}

/// internal args
Dynamic libargs(Args args)
{
    return dynamic(Runtime.args.map!(x => dynamic(x)).array);
}

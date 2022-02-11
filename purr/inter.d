module purr.inter;

import std.typecons;
import std.traits;
import purr.io;
import std.functional;
import std.conv;
import std.algorithm;
import std.meta;
import purr.vm;
import purr.bc.dump;
import purr.bytecode;
import purr.base;
import purr.ast.ast;
import purr.dynamic;
import purr.parse;
import purr.vm;
import purr.inter;
import purr.srcloc;
import purr.ir.repr;
import purr.ir.walk;
import purr.ctx;

__gshared bool dumpbytecode = false;
__gshared bool dumpir = false;

/// vm callback that sets the locals defined into the root base 
LocalCallback exportLocalsToBaseFormback(Context ctx, Bytecode func)
{
    LocalCallback ret = (uint index, Dynamic[] locals) {
        most: foreach (i, v; locals)
        {
            foreach (ref rb; ctx.rootBase)
            {
                if (rb.name == func.stab[i])
                {
                    rb.val = v;
                    continue most;
                }
            }
            ctx.rootBase ~= Pair(func.stab[i], v);
        }
        outer: foreach (i, pv; func.captured)
        {
            if (pv is null || i >= func.captab.length)
            {
                continue outer;
            }
            Dynamic v = *pv;
            foreach (ref rb; ctx.rootBase)
            {
                if (rb.name == func.captab[i])
                {
                    rb.val = v;
                    continue outer;
                }
            }
            ctx.rootBase ~= Pair(func.captab[i], v);
        }
    };
    return ret;
} 

Dynamic evalImpl(Walker)(Context ctx, SrcLoc code, Args args)
{
    Node node = code.parse;
    Walker walker = new Walker;
    Bytecode func = walker.walkProgram(node, ctx);
    if (dumpbytecode)
    {
        OpcodePrinter oppr = new OpcodePrinter;
        oppr.walk(func);
        writeln(oppr.ret);
    }
    return run(func, args, ctx.exportLocalsToBaseFormback(func));
}

Dynamic eval(Context ctx, SrcLoc code, Args args=new Dynamic[0])
{
    return evalImpl!(purr.ir.walk.Walker)(ctx, code, args);
}

void define(T)(Context ctx, string name, T value)
{
    ctx.rootBase ~= Pair(name, value.toDynamic);
}

module purr.ctx;

import purr.dynamic;
import purr.base;
import purr.bytecode;
import purr.plugin.plugins;

class Context {
    Pair[] rootBase;
    
    this()
    {
    }

    static Context empty()
    {
        return new Context;
    }

    static Context base()
    {
        Context ret = new Context;
        ret.rootBase = pluginLib;
        return ret;
    }
        
    Dynamic*[] loadBase()
    {
        Dynamic*[] ret;
        foreach (i; rootBase)
        {
            ret ~= new Dynamic(i.val);
        }
        return ret;
    }

    Bytecode baseFunction()
    {
        Bytecode func = new Bytecode;
        func.stab = baseFunctionLookup;
        func.captured = loadBase;
        return func;
    }

    Mapping baseObject()
    {
        Mapping ret;
        foreach (pair; rootBase)
        {
            ret[pair.name.dynamic] = pair.val;
        }
        return ret;
    }

    Bytecode.Lookup baseFunctionLookup()
    {
        Bytecode.Lookup stab = Bytecode.Lookup(null, null);
        foreach (name; rootBase)
        {
            stab.define(name.name);
        }
        return stab;
    }
}
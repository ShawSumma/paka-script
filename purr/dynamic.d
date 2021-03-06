module purr.dynamic;

import core.sync.mutex;
import core.memory;
import core.atomic;
import std.algorithm;
import std.conv;
import std.array;
import std.traits;
import purr.io;
import purr.bytecode;
import purr.vm;
import purr.data.map;
import purr.data.rope;
import purr.plugin.syms;

version = safe;

alias Dynamic = DynamicImpl;
alias Table = TableImpl;

alias Args = Dynamic[];
alias Array = Dynamic[];

alias Delegate = Dynamic function(Args);
alias Mapping = Dynamic[Dynamic];
pragma(inline, true):
Mapping emptyMapping()
{
    return Mapping.init;
}

private __gshared size_t symc = 0;
Dynamic gensym()
{
    synchronized
    {
        return dynamic(symc++);
    }
}

void*[] beforeTables;

void*[] lookingFor;

shared size_t tableVersion;

final class TableImpl
{
    Mapping table = emptyMapping;
    alias table this;

pragma(inline, true):
    static Table empty()
    {
        return new Table;
    }

    this()
    {
        table = emptyMapping;
    }

    this(typeof(table) t)
    {
        table = t;
    }

    this(typeof(table) t, Table m)
    {
        table = t;
    }

    Dynamic rawIndex(Dynamic key)
    {
        if (Dynamic* d = key in table)
        {
            return *d;
        }
        throw new Exception("key not found: " ~ key.to!string);
    }

    void rawSet(Dynamic key, Dynamic value)
    {
        table[key] = value;
    }

    void set(Dynamic key, Dynamic value)
    {
        Dynamic* metaset = dynamic("set") in table;
        if (metaset !is null)
        {
            (*metaset)([dynamic(this), key, value]);
        }
        rawSet(key, value);
    }

    Dynamic opIndex(Dynamic key)
    {
        if (Dynamic* val = key in this)
        {
            return *val;
        }
        throw new Exception("key not found: " ~ key.to!string);
    }

    Dynamic* opBinaryRight(string op : "in")(Dynamic other)
    {
        foreach (i; lookingFor)
        {
            if (i is cast(void*) this)
            {
                return null;
            }
        }
        lookingFor ~= cast(void*) this;
        scope (exit)
        {
            lookingFor.length--;
        }
        Dynamic* ret = other in table;
        if (ret)
        {
            return ret;
        }
        Dynamic* metaget = "get".dynamic in table;
        if (metaget is null)
        {
            return null;
        }
        if (metaget.isArray)
        {
            foreach (getter; metaget.arr)
            {
                if (Dynamic* got = other in getter.tab)
                {
                    return got;
                }
            }
            return null;
        }
        else if (metaget.isTable)
        {
            return other in (*metaget).tab;
        }
        else
        {
            return new Dynamic((*metaget)([this.dynamic, other]));
        }
    }

    Dynamic opBinary(string op)(Dynamic other)
    {
        enum string opname(string op)()
        {
            switch (op)
            {
            default : assert(0);
            case "~" : return "cat";
            case "+" : return "add";
            case "-" : return "sub";
            case "*" : return "mul";
            case "/" : return "div";
            case "%" : return "mod";
            }
        }
        return table[dynamic(opname!op)]([dynamic(this), other]);
    }

    Dynamic opCall(Args args)
    {
        if (Dynamic* index = "index".dynamic in table)
        {
            if (Dynamic* dyn = "self".dynamic in table)
            {
                return table[dynamic("index")](dyn.arr ~ args);
            }
            return table[dynamic("index")](args);
        }
        if (Dynamic* ret = args[0] in table)
        {
            return *ret;
        }
        throw new Exception("cannot call or index table");
    }

    Dynamic opUnary(string op: "-")()
    {
        return table[dynamic("neg")]([this]);
    }

    override string toString()
    {
        foreach (i, v; beforeTables)
        {
            if (v is cast(void*) this)
            {
                return "&" ~ i.to!string;
            }
        }
        beforeTables ~= cast(void*) this;
        scope (exit)
        {
            beforeTables.length--;
        }
        Dynamic* str = "str".dynamic in table;
        if (str !is null)
        {
            Dynamic res = *str;
            if (res.isString)
            {
                res = res([dynamic(this)]);
            }
            if (res.isString)
            {
                throw new Exception("str must return a string");
            }
            return res.toString;
        }
        return rawToString;
    }

    string rawToString()
    {
        char[] ret;
        ret ~= "{";
        size_t i = 0;
        foreach (key, value; table)
        {
            if (i != 0)
            {
                ret ~= ", ";
            }
            ret ~= key.to!string;
            ret ~= ": ";
            ret ~= value.to!string;
            i++;
        }
        ret ~= "}";
        return cast(string) ret;
    }
}

template native(alias func)
{
    alias native = impl;

    shared static this()
    {
        syms[func.mangleof] = &func;
    }

    Fun impl()
    {
        Fun fun = Fun(&func);
        fun.mangled = func.mangleof;
        return fun;

    }
}

alias Fun = FunStruct;

struct FunStruct
{
    Dynamic function(Args) value;
    string mangled;
    string[] args;
    string toString()
    {
        return callableFormat(args);
    }
}

Dynamic dynamic(T...)(T a)
{
    return Dynamic(a);
}

struct DynamicImpl
{
    enum Type : ubyte
    {
        nil,
        log,
        sml,
        sym,
        str,
        tup,
        arr,
        tab,
        fun,
        pro,
    }

    union Value
    {
        bool log;
        double sml;
        string str;
        Dynamic[] arr;
        Table tab;
        alias Formable = FormableUnion;
        union FormableUnion
        {
            Fun* fun;
            Bytecode pro;
        }

        Formable fun;
    }

    Type type = void;
    Value value = void;

pragma(inline, true):
    static Dynamic strToNum(string s)
    {
        return dynamic(s.to!double);
    }

    static Dynamic sym(string s)
    {
        Dynamic ret = dynamic(s);
        ret.type = Type.sym;
        return ret;
    }

    static Dynamic tuple(Array a)
    {
        Dynamic ret = dynamic(a);
        ret.type = Type.tup;
        return ret;
    }

    this(Type t)
    {
        type = t;
    }

    this(bool log)
    {
        value.log = log;
        type = Type.log;
    }

    this(double num)
    {
        value.sml = num;
        type = Type.sml;
    }

    this(string str)
    {
        value.str = str;
        type = Type.str;
    }

    this(Array arr)
    {
        value.arr = arr;
        type = Type.arr;
    }

    this(Mapping tab)
    {
        value.tab = new Table(tab);
        type = Type.tab;
    }

    this(Table tab)
    {
        value.tab = tab;
        type = Type.tab;
    }

    this(Fun fun)
    {
        value.fun.fun = [fun].ptr;
        type = Type.fun;
    }

    this(Bytecode pro)
    {
        value.fun.pro = pro;
        type = Type.pro;
    }

    this(Dynamic other)
    {
        set(other);
    }

    void set(Dynamic other)
    {
        type = other.type;
        value = other.value;
    }

    static Dynamic nil()
    {
        Dynamic ret = dynamic(false);
        ret.value = Dynamic.Value.init;
        ret.type = Type.nil;
        return ret;
    }

    string toString()
    {
        return strFormat(this);
    }

    Dynamic opCall(Args args)
    {
        switch (type)
        {
        case Type.fun:
            return fun.fun.value(args);
        case Type.pro:
            return run(fun.pro, args);
        case Type.tab:
            return value.tab(args);
        case Type.tup:
            return arr[args[0].as!size_t];
        case Type.arr:
            return arr[args[0].as!size_t];
        default:
            throw new Exception("error: not a function: " ~ this.to!string);
        }
    }

    void opIndexAssign(Dynamic setto, Dynamic key)
    {
        switch (type)
        {
        case Type.tab:
            tab.set(key, setto);
            break;
        case Type.tup:
            value.arr[key.as!size_t] = setto;
            break;
        case Type.arr:
            value.arr[key.as!size_t] = setto;
            break;
        default:
            throw new Exception("error: not a function: " ~ this.to!string);
        }
    }

    Dynamic opIndex(Dynamic other)
    {
        switch (type)
        {
        case Type.tab:
            return value.tab[other];
        case Type.tup:
            return arr[other.as!size_t];
        case Type.arr:
            return arr[other.as!size_t];
        default:
            throw new Exception("error: not a function: " ~ this.to!string);
        }
    }

    int opCmp(Dynamic other)
    {
        return cmpDynamic(this, other);
    }

    int flatOpCmp(Dynamic other)
    {
        Type t = type;
        switch (t)
        {
        default:
            throw new Exception("error: not comparable: " ~ this.to!string ~ " " ~ other.to!string);
        case Type.nil:
            return 0;
        case Type.log:
            return value.log - other.log;
        case Type.sml:
            double a = as!double;
            double b = other.value.sml;
            if (a < b)
            {
                return -1;
            }
            if (a == b)
            {
                return 0;
            }
            return 1;
        case Type.str:
            return cmp(value.str, other.str);
        }
    }

    size_t toHash() const nothrow
    {
        final switch (type)
        {
        case Type.nil:
            return 0;
        case Type.log:
            if (value.log)
            {
                return 1;
            }
            else
            {
                return 2;
            }
        case Type.sml:
            if (value.sml > 0)
            {
                return 3 + cast(size_t) value.sml;
            }
            else
            {
                return 3 + cast(size_t)-value.sml;
            }
        case Type.sym:
            return value.str.hashOf;
        case Type.str:
            return value.str.hashOf;
        case Type.tup:
            return size_t.max - 4;
        case Type.arr:
            return size_t.max - 5;
        case Type.tab:
            return value.tab.table.length + 1 << 34;
        case Type.fun:
            return size_t.max - 3;
        case Type.pro:
            return size_t.max - 2;
        }
    }

    bool opEquals(const Dynamic other) const
    {
        return cmpDynamic(cast(Dynamic) this, cast(Dynamic) other) == 0;
    }

    bool isSameObject(const Dynamic other) const
    {
        if (other.type != type)
        {
            return false;
        }
        switch (type)
        {
        default:
            assert(false);
        case Type.nil:
            return true;
        case Type.log:
            return value.log == other.value.log;
        case Type.sml:
            return value.sml == other.value.sml;
        case Type.sym:
            return value.str ==other.value.str;
        case Type.str:
            return value.str == other.value.str;
        case Type.tup:
            return cast(void*) value.arr == cast(void*) other.value.arr;
        case Type.arr:
            return cast(void*) value.arr == cast(void*) other.value.arr;
        case Type.tab:
            return value.tab is other.value.tab;
        case Type.fun:
            return cast(void*) value.fun.fun == cast(void*) other.value.fun.fun;
        case Type.pro:
            return cast(void*) value.fun.pro == cast(void*) other.value.fun.pro;
        }
    }

    bool opEquals(Dynamic other)
    {
        return cmpDynamic(this, other) == 0;
    }

    Dynamic opBinary(string op)(Dynamic other)
    {
        static if (op != "~")
        {
            if (type == Type.sml && other.type == Type.sml)
            {
                return dynamic(mixin("value.sml " ~ op ~ " other.value.sml"));
            }
            if (type == Type.tab)
            {
                return mixin("tab " ~ op ~ " other");
            }
        }
        static if (op == "~" || op == "+")
        {
            if (type == Type.str && other.type == Type.str)
            {
                return dynamic(str ~ other.str);
            }
            if (type == Type.arr && other.type == Type.arr)
            {
                return dynamic(arr ~ other.arr);
            }
        }
        throw new Exception("invalid types: " ~ type.to!string ~ op ~ other.type.to!string);
    }

    Dynamic opUnary(string op)()
    {
        return dynamic(mixin(op ~ "as!double"));
    }

    bool log()
    {
        version (safe)
        {
            if (type != Type.log)
            {
                throw new Exception("expected logical type (not: " ~ this.to!string ~ ")");
            }
        }
        return value.log;
    }

    string str()
    {
        version (safe)
        {
            if (type != Type.str)
            {
                throw new Exception("expected string type (not: " ~ this.to!string ~ ")");
            }
        }
        return value.str;
    }

    Array arr()
    {
        version (safe)
        {
            if (!isArray)
            {
                throw new Exception("expected array type (not: " ~ this.to!string ~ ")");
            }
        }
        return value.arr;
    }

    Table tab()
    {
        version (safe)
        {
            if (type != Type.tab)
            {
                throw new Exception("expected table type (not: " ~ this.to!string ~ ")");
            }
        }
        return value.tab;
    }

    bool isCallable() {
        return type == Type.fun || type == Type.pro;
    }

    Value.Formable fun()
    {
        version (safe)
        {
            if (type != Type.fun && type != Type.pro)
            {
                throw new Exception("expected callable type not " ~ type.to!string);
            }
        }
        return value.fun;
    }

    double num() 
    {
        version (safe)
        {
            if (type != Type.sml)
            {
                throw new Exception("expected number type (not: " ~ this.to!string ~ ")");
            }
        }
        return value.sml; 
    }

    T as(T)() if (isIntegral!T)
    {
        if (type == Type.sml)
        {
            return cast(T) value.sml;
        }
        else
        {
            throw new Exception("expected numeric type (not: " ~ this.to!string ~ ")");
        }
    }

    T as(T)() if (isFloatingPoint!T)
    {
        if (type == Type.sml)
        {
            return cast(T) value.sml;
        }
        else
        {
            throw new Exception("expected numeric type (not: " ~ this.to!string ~ ")");
        }
    }

    bool isNil()
    {
        return type == Type.nil;
    }

    bool isString()
    {
        return type == Type.str;
    }

    bool isNumber()
    {
        return type == Type.sml;
    }

    bool isArray()
    {
        return type == Type.arr || type == Type.tup;
    }

    bool isTable()
    {
        return type == Type.tab;
    }

    bool isTruthy()
    {
        return type != Type.nil && (type != Type.log || value.log);
    }

    static private int cmpDynamic(Dynamic a, Dynamic b)
    {
    redo:
        if (b.type != a.type)
        {
            return cmp(a.type, b.type);
        }
        switch (a.type)
        {
        default:
            assert(false);
        case Type.nil:
            return 0;
        case Type.log:
            return cmp(a.value.log, b.value.log);
        case Type.sym:
            return cmp(a.value.str, b.value.str);
        case Type.str:
            return cmp(a.value.str, b.value.str);
        case Type.sml:
            return cmp(a.value.sml, b.value.sml);
        case Type.tup:
            Dynamic[2] cur = [a, b];
            foreach (i, p; above)
            {
                if (cur[0] is p[0] && cur[1] is p[1])
                {
                    return 0;
                }
            }
            above ~= cur;
            scope (exit)
            {
                above.length--;
            }
            const Dynamic[] as = a.arr;
            const Dynamic[] bs = b.arr;
            if (int c = cmp(as.length, bs.length))
            {
                return c;
            }
            foreach (i; 0 .. as.length)
            {
                if (int res = cmpDynamic(as[i], bs[i]))
                {
                    return res;
                }
            }
            return 0;
        case Type.arr:
            Dynamic[2] cur = [a, b];
            foreach (i, p; above)
            {
                if (cur[0] is p[0] && cur[1] is p[1])
                {
                    return 0;
                }
            }
            above ~= cur;
            scope (exit)
            {
                above.length--;
            }
            const Dynamic[] as = a.arr;
            const Dynamic[] bs = b.arr;
            if (int c = cmp(as.length, bs.length))
            {
                return c;
            }
            foreach (i; 0 .. as.length)
            {
                if (int res = cmpDynamic(as[i], bs[i]))
                {
                    return res;
                }
            }
            return 0;
        case Type.tab:
            Dynamic[2] cur = [a, b];
            foreach (i, p; above)
            {
                if (cur[0] is p[0] && cur[1] is p[1])
                {
                    return 0;
                }
            }
            above ~= cur;
            scope (exit)
            {
                above.length--;
            }
            return cmpTable(a.value.tab, b.value.tab);
        case Type.fun:
            return cmp(a.value.fun.fun, b.value.fun.fun);
        case Type.pro:
            return cmpFunction(a.value.fun.pro, b.value.fun.pro);
        }
    }

    private static string strFormat(Dynamic dyn)
    {
        foreach (i, v; before)
        {
            if (dyn is v)
            {
                return "&" ~ i.to!string;
            }
        }
        before ~= dyn;
        scope (exit)
        {
            before.length--;
        }
    redo:
        final switch (dyn.type)
        {
        case Type.nil:
            return "nil";
        case Type.log:
            return dyn.log.to!string;
        case Type.sml:
            if (dyn.value.sml % 1 == 0 && dyn.value.sml > long.min && dyn.value.sml < long.max)
            {
                return to!string(cast(long) dyn.value.sml);
            }
            return dyn.value.sml.to!string;
        case Type.sym:
            return ':' ~ dyn.value.str;
        case Type.str:
            return '"' ~ dyn.str ~ '"';
        case Type.tup:
            char[] ret;
            ret ~= "(";
            foreach (i, v; dyn.arr)
            {
                if (i != 0)
                {
                    ret ~= ", ";
                }
                ret ~= v.to!string;
            }
            ret ~= ")";
            return cast(string) ret;
        case Type.arr:
            char[] ret;
            ret ~= "[";
            foreach (i, v; dyn.arr)
            {
                if (i != 0)
                {
                    ret ~= ", ";
                }
                ret ~= v.to!string;
            }
            ret ~= "]";
            return cast(string) ret;
        case Type.tab:
            return dyn.tab.toString;
        case Type.fun:
            return (*dyn.value.fun.fun).to!string;
        case Type.pro:
            return dyn.fun.pro.to!string;
        }
    }

    private static int cmpFunction(const Bytecode a, const Bytecode b)
    {
        return cmp(cast(void*) a, cast(void*) b);
    }
}

private Dynamic[] before = null;
private Table[2][] tableAbove;
private Dynamic[2][] above;

int cmp(T)(T a, T b) if (!is(T == Bytecode) && !is(T == Dynamic))
{
    if (a == b)
    {
        return 0;
    }
    if (a < b)
    {
        return -1;
    }
    return 1;
}

int cmpTable(Table at, Table bt)
{
    foreach (i, p; tableAbove)
    {
        if (at is p[0] && bt is p[1])
        {
            return 0;
        }
    }
    tableAbove ~= [at, bt];
    scope (exit)
    {
        tableAbove.length--;
    }
    if (int c = cmp(at.table.length, bt.table.length))
    {
        return c;
    }
    foreach (key, value; at)
    {
        const Dynamic* bValue = key in bt;
        if (bValue is null)
        {
            foreach (key2, value2; bt)
            {
                if (key2 !in at)
                {
                    return Dynamic.cmpDynamic(key, key2);
                }
            }
            assert(0);
        }
        if (int res = Dynamic.cmpDynamic(value, *bValue))
        {
            return res;
        }
    }
    return 0;
}

string callableFormat(string[] args)
{
    string argsRepr;
    if (args.length != 0)
    {
        argsRepr = "(" ~ args.join(",") ~ ") ";
    }
    return "lambda" ~ argsRepr ~ "{...}";
}

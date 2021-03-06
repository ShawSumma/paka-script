module ext.paka.parse.parse;

import purr.io;
import std.conv;
import std.file;
import std.array;
import std.utf;
import std.ascii;
import std.string;
import std.algorithm;
import std.functional;
import purr.vm;
import purr.inter;
import purr.dynamic;
import purr.srcloc;
import purr.base;
import purr.fs.disk;
import purr.fs.har;
import purr.fs.memory;
import purr.fs.files;
import purr.bytecode;
import purr.ir.walk;
import purr.ast.ast;
import purr.ctx;
import ext.paka.built;
import ext.paka.parse.tokens;
import ext.paka.parse.util;
import ext.paka.parse.op;

/// reads open parens
Node[][] readCallArgs(TokenArray tokens) 
{
    Node[][] ret;
    Node[] args;
    tokens.nextIs(Token.Type.open, "(");
    while (!tokens.first.isClose(")"))
    {
        if (tokens.first.isSemicolon)
        {
            tokens.nextIs(Token.Type.semicolon);
            ret ~= args;
            args = null;
        }
        else
        {
            args ~= tokens.readExprBase;
            if (tokens.first.isComma)
            {
                tokens.nextIs(Token.Type.comma);
            }
        }
    }
    tokens.nextIs(Token.Type.close, ")");
    ret ~= args;
    return ret;
}

Node[] readParens(TokenArray tokens) 
{
    Node[][] ret = tokens.readCallArgs;
    if (ret.length > 1)
    {
        throw new Exception("unexpected semicolon in (...)");
    }
    return ret[0];
}

/// reads square brackets
Node[] readSquare(TokenArray tokens) 
{
    Node[] args;
    tokens.nextIs(Token.Type.open, "[");
    while (!tokens.first.isClose("]"))
    {
        args ~= tokens.readExprBase;
        if (tokens.first.isComma)
        {
            tokens.nextIs(Token.Type.comma);
        }
    }
    tokens.nextIs(Token.Type.close, "]");
    return args;
}

// /// strips newlines and changes the input
void stripNewlines(TokenArray tokens)
{
    while (tokens.first.isSemicolon)
    {
        tokens.nextIs(Token.Type.semicolon);
    }
}

Node readPostCallExtend(TokenArray tokens, Node last)
{
    Node[][] args = tokens.readCallArgs;
    while (tokens.first.isOpen("{") || tokens.first.isOperator("->"))
    {
        args[$ - 1] ~= new Form("fun", [new Form("args"), tokens.readBlock]);
    }
    foreach (argList; args)
    {
        last = new Form("call", last ~ argList);
    }
    return last;
}

/// after reading a small expression, read a postfix expression
alias readPostExtend = Spanning!(readPostExtendImpl, Node);
Node readPostExtendImpl(TokenArray tokens, Node last)
{
    if (!tokens.first.exists)
    {
        return last;
    }
    Node ret = void;
    if (tokens.first.isOpen("("))
    {
        ret = tokens.readPostCallExtend(last);
    }
    else if (tokens.first.isOperator("."))
    {
        tokens.nextIs(Token.Type.operator, ".");
        if (tokens.first.isOpen("["))
        {
            Node[] arr = tokens.readSquare;
            ret = new Form("index", last, arr);
        }
        else if (tokens.first.isOpen("("))
        {
            Node[] arr = tokens.readParens;
            ret = new Form("index", last, arr);
        }
        else 
        {
            Node key = void;
            if (tokens.first.value[0].isDigit)
            {
                key = new Value(tokens.first.value.to!double);
            }
            else
            {
                key = new Value(tokens.first.value);
            }
            tokens.nextIs(Token.Type.ident);
            if (Form form = cast(Form) last)
            {
                if (form.form == "cache")
                {
                    last = form.args[0];
                }
                if (form.form == "do")
                {
                    if (Form form2 = cast(Form) form.args[$-1])
                    {
                        if (form2.form == "cache")
                        {
                            last = new Form("do", form.args[0..$-1], form2.args[0]);
                        }
                    }
                }
            }
            // Node sym = genSym;
            // Node setsym = new Form("set", sym, last);
            // Node indexed = new Form("index", sym, key);
            // Node res = new Form("cache", indexed, sym);
            // Node res = indexed;
            // ret = new Form("do", setsym, res);
            ret = new Form("index", last, key);
        }
    }
    else
    {
        return last; // throw new Exception("parse error " ~ tokens.to!string);
    }
    return tokens.readPostExtend(ret);
}

/// read an if statement
alias readIf = Spanning!readIfImpl;
Node readIfImpl(TokenArray tokens)
{
    Node cond = tokens.readExprBase;
    Node iftrue = tokens.readBlock;
    Node iffalse;
    if (tokens.first.isKeyword("else"))
    {
        tokens.nextIs(Token.Type.keyword, "else");
        iffalse = tokens.readBlock;
    }
    else
    {
        iffalse = new Value(Dynamic.nil);
    }
    return new Form("if", cond, iftrue, iffalse);
}
/// read an if statement
alias readWhile = Spanning!readWhileImpl;
Node readWhileImpl(TokenArray tokens)
{
    Node cond = tokens.readExprBase;
    Node block = tokens.readBlock;
    return new Form("while", cond, block);
}

alias readTable = Spanning!readTableImpl;
Ident thisSym = null;

Node readTableImpl(TokenArray tokens)
{
    Ident prev = thisSym;
    scope(exit) thisSym = prev;
    thisSym = genSym;
    Node set = new Form("set", thisSym, new Form("table"));
    Node build = tokens.readBlock;
    return new Form("do", set, build, thisSym);
}

void skip1(ref string str, ref Span span)
{
    if (str[0] == '\n')
    {
        span.first.line += 1;
        span.first.column = 1;
    }
    else
    {
        span.first.column += 1;
    }
    str = str[1 .. $];
}

bool isDigitInBase(char c, long base)
{
    if (base > 0 && base < 10)
    {
        return c - '0' < base;
    }
    if (base == 10)
    {
        return c.isDigit;
    }
    if (base > 10)
    {
        long val = c;
        if (val >= 'A' && val <= 'A')
        {
            val = val - 'A' + 'a';
        }
        bool isLetterDigit = val >= 10 && val < base;
        return isLetterDigit || c.isDigitInBase(10);
    }
    throw new Exception("base not valud: " ~ base.to!string);
}

long parseNumberOnly(ref string input, size_t base)
{
    string str;
    while (input.length != 0 && input[0].isDigitInBase(base))
    {
        str ~= input[0];
        input = input[1 .. $];
    }
    if (str.length == 0)
    {
        throw new Exception("found no digits when parse escape in base " ~ base.to!string);
    }
    return str.to!size_t(cast(uint) base);
}

size_t escapeNumber(ref string input)
{
    if (input[0] == '0')
    {
        char ctrlchr = input[1];
        input = input[2 .. $];
        switch (ctrlchr)
        {
        case 'b':
            return input.parseNumberOnly(2);
        case 'o':
            return input.parseNumberOnly(8);
        case 'n':
            size_t base = input.escapeNumber;
            if (input.length < 1 || input[0] != ':')
            {
                string why = "0n" ~ base.to!string ~ " must be followd by a colon (:)";
                throw new Exception("cannot have escape: " ~ why);
            }
            input = input[1 .. $];
            if (base == 1)
            {
                size_t num;
                while (input.length != 0 && input[0] == '0')
                {
                    num++;
                }
                return num;
            }
            if (base > 36)
            {
                string why = "0n must be followed by a number 1 to 36 inclusive";
                throw new Exception("cannot have escape: " ~ why);
            }
            return input.parseNumberOnly(base);
        case 'x':
            return input.parseNumberOnly(16);
        default:
            string why = "0 must be followed by one of: nbox";
            throw new Exception("cannot have escape: " ~ why);
        }
    }
    else
    {
        return input.parseNumberOnly(10);
    }
}

Node readStringPart(ref string str, ref Span span)
{
    Span spanInput = span;
    char first = str[0];
    if (first == '\\')
    {
        str.skip1(span);
    }
    string ret;
    while (str.length != 0 && str[0] != '\\')
    {
        ret ~= str[0];
        str.skip1(span);
    }
    Node node = void;
    if (first != '\\')
    {
        node = new Value(ret);
    }
    else
    {
        str.skip1(span);
        if ((ret[0] == 'u' && ret[1] == 'f') || (ret[0] == 'f' && ret[1] == 'u'))
        {
            string input = ret[3 .. $ - 1].strip;
            node = SrcLoc(spanInput.first.line, spanInput.first.column, "string", input ~ ";")
                .parsePakaAs!readExprBase;
            node = new Form("call", [new Ident("_unicode_ctrl"), node]);
        }
        else if (ret[0] == 'f')
        {
            string input = ret[2 .. $ - 1].strip;
            node = SrcLoc(spanInput.first.line, spanInput.first.column, "string", input ~ ";")
                .parsePakaAs!readExprBase;
        }
        else if (ret[0] == 'u')
        {
            string input = ret[2 .. $ - 1].strip;
            node = new Form("call", [new Ident("_unicode_ctrl"), new Value(input)]);
        }
        else
        {
            assert(false);
        }
    }
    node.span = spanInput;
    return node;
}

/// reads first element of postfix expression
alias readPostExpr = Spanning!readPostExprImpl;
Node readPostExprImpl(TokenArray tokens)
{
    Node last = void;
    if (tokens.first.isKeyword("lambda"))
    {
        tokens.nextIs(Token.Type.keyword, "lambda");
        if (tokens.first.isOpen("("))
        {
            last = new Form("fun", [
                    new Form("args", tokens.readParens), tokens.readBlock
                    ]);
        }
        else if (tokens.first.isOpen("{") || tokens.first.isOperator("->"))
        {
            last = new Form("fun", new Form("args"), tokens.readBlock);
        }
    }
    else if (tokens.first.isOpen("("))
    {
        Node[] nodes = tokens.readParens;
        if (nodes.length == 0)
        {
            last = new Value(Dynamic.nil);
        }
        else if (nodes.length == 1)
        {
            last = nodes[0];
        }
        else
        {
            last = new Form("tuple", nodes);
        }
    }
    else if (tokens.first.isOpen("["))
    {
        last = new Form("array", tokens.readSquare);
    }
    else if (tokens.first.isKeyword("cache"))
    {
        tokens.nextIs(Token.Type.keyword, "cache");
        Node[] checks = void;
        if (tokens.first.isOpen("("))
        {
            checks = tokens.readParens;
        }
        else
        {
            checks = null;
        }
        if (tokens.first.isOpen("{") || tokens.first.isOperator("->"))
        {
            last = new Form("cache", tokens.readBlock, checks);
        }
        else
        {
            last = new Form("cache", tokens.readPostExpr, checks);
        }
    }
    else if (tokens.first.isKeyword("table"))
    {
        tokens.nextIs(Token.Type.keyword, "table");
        last = tokens.readTable;
    }
    else if (tokens.first.isKeyword("if"))
    {
        tokens.nextIs(Token.Type.keyword, "if");
        last = tokens.readIf;
    }
    else if (tokens.first.isKeyword("while"))
    {
        tokens.nextIs(Token.Type.keyword, "while");
        last = tokens.readWhile;
    }
    else if (tokens.first.isKeyword("true"))
    {
        tokens.nextIs(Token.Type.keyword, "true");
        last = new Value(true);
    }
    else if (tokens.first.isKeyword("false"))
    {
        tokens.nextIs(Token.Type.keyword, "false");
        last = new Value(false);
    }
    else if (tokens.first.isKeyword("nil"))
    {
        tokens.nextIs(Token.Type.keyword, "nil");
        last = new Value(Dynamic.nil);
    }
    else if (tokens.first.isIdent)
    {
        if (tokens.first.value[0] == '$')
        {
            last = new Ident(tokens.first.value);
            tokens.nextIs(Token.Type.ident);
        }
        else if (tokens.first.value[0].isDigit)
        {
            last = new Value(tokens.first.value.to!double);
            tokens.nextIs(Token.Type.ident);
        }
        else if (tokens.first.value[0] == '@')
        {
            if (thisSym is null) {
                throw new Exception("cannot use " ~ tokens.first.value ~ " outside of table{...}");
            }
            Node index = new Value(tokens.first.value[1 .. $]);
            tokens.nextIs(Token.Type.ident);
            last = new Form("index", thisSym, index);
        }
        // else
        // {
        //     Node var = new Ident("this");
        //     Node index = new Value(tokens.first.value);
        //     tokens.nextIs(Token.Type.ident);
        //     last = new Form("cache", new Form("index", var, index));
        // }
    else
        {
            last = new Ident(tokens.first.value);
            tokens.nextIs(Token.Type.ident);
        }
    }
    else if (tokens.first.isString)
    {
        if (!tokens.first.value.canFind('\\'))
        {
            last = new Value(tokens.first.value);
        }
        else
        {
            Node[] args;
            string value = tokens.first.value;
            Span span = tokens.first.span;
            while (value.length != 0)
            {
                args ~= value.readStringPart(span);
            }
            last = new Form("call", new Value(native!strConcat), args);
        }
        tokens.nextIs(Token.Type.string);
    }
    return tokens.readPostExtend(last);
}

/// read prefix before postfix expression.
alias readPreExpr = Spanning!readPreExprImpl;
Node readPreExprImpl(TokenArray tokens)
{
    if (tokens.first.isOperator)
    {
        string[] vals;
        while (tokens.first.isOperator)
        {
            vals ~= tokens.first.value;
            tokens.nextIs(Token.Type.operator);
        }
        return parseUnaryOp(vals)(tokens.readPostExpr);
    }
    return tokens.readPostExpr;
}

bool isDotOperator(Token tok)
{
    return tok.isOperator("!") || tok.isOperator("\\");
}

alias readExprBase = Spanning!(readExprBaseImpl);
/// reads any expresssion with precedence of zero
Node readExprBaseImpl(TokenArray tokens)
{
    return tokens.readExpr(0);
}

bool isAnyOperator(Token tok, string[] ops)
{
    foreach (op; ops)
    {
        if (tok.isOperator(op))
        {
            return true;
        }
    }
    return false;
}

alias readExpr = Spanning!(readExprImpl, size_t);
/// reads any expresssion
Node readExprImpl(TokenArray tokens, size_t level)
{
    if (level == prec.length)
    {
        return tokens.readPreExpr;
    }
    string[][] opers;
    Node[] subNodes = [tokens.readExpr(level + 1)];
    while (tokens.first.isAnyOperator(prec[level]) || tokens.first.isDotOperator)
    {
        string[] oper;
        while (tokens.first.isDotOperator)
        {
            oper ~= tokens.first.value;
            tokens.nextIs(Token.Type.operator);
        }
        oper ~= tokens.first.value;
        tokens.nextIs(Token.Type.operator);
        while (tokens.first.isDotOperator)
        {
            oper ~= tokens.first.value;
            tokens.nextIs(Token.Type.operator);
        }
        subNodes ~= tokens.readExpr(level + 1);
        opers ~= oper;
    }
    Node ret = subNodes[0];
    Ident last;
    foreach (i, oper; opers)
    {
        ret = parseBinaryOp(oper)(ret, subNodes[i + 1]);
    }
    return ret;
}

/// reads any statement ending in a semicolon
alias readStmt = Spanning!readStmtImpl;
Node readStmtImpl(TokenArray tokens)
{
    scope (exit)
    {
        while (tokens.first.isSemicolon)
        {
            tokens.nextIs(Token.Type.semicolon);
        }
    }
    if (tokens.first.isKeyword("return"))
    {
        tokens.nextIs(Token.Type.keyword, "return");
        return new Form("return", tokens.readExprBase);
    }
    if (tokens.first.isKeyword("def"))
    {
        tokens.nextIs(Token.Type.keyword, "def");
        Form call = cast(Form) tokens.readExprBase;
        assert(call);
        Node name = new Form("args", call.args[0 .. $ - 1]);
        Form fun = cast(Form) call.args[$ - 1];
        assert(fun);
        Node dobody = fun.args[$ - 1];
        // Node dobody = tokens.readBlock;
        return new Form("set", name, dobody);
    }
    return tokens.readExprBase;
}

/// reads many staments statement, each ending in a semicolon
/// does not read brackets surrounding
alias readBlockBody = Spanning!readBlockBodyImpl;
Node readBlockBodyImpl(TokenArray tokens)
{
    Node[] ret;
    while (tokens.first.exists && !tokens.first.isClose("}") && !tokens.first.isKeyword("else"))
    {
        SrcLoc loc = tokens.position;
        ret ~= tokens.readStmt;
        if (tokens.position.isAt(loc))
        {
            break;
        }
    }
    return new Form("do", ret);
}

/// wraps the readblock and consumes curly braces
alias readBlock = Spanning!readBlockImpl;
Node readBlockImpl(TokenArray tokens)
{
    if (tokens.first.isOperator("->"))
    {
        tokens.nextIs(Token.Type.operator, "->");
        return tokens.readStmt;
    }
    else
    {
        tokens.nextIs(Token.Type.open, "{");
        Node ret = readBlockBody(tokens);
        tokens.nextIs(Token.Type.close, "}");
        return ret;
    }
}

alias parsePakaValue = parsePakaAs!readBlockBodyImpl;
alias parsePaka = parsePakaValue;
/// parses code as the paka programming language
Node parsePakaAs(alias parser)(SrcLoc loc)
{
    TokenArray tokens = new TokenArray(loc);
    try
    {
        Node node = parser(tokens);
        return node;
    }
    catch (Error e)
    {
        string[] lines = loc.src.split("\n");
        size_t[] nums;
        size_t ml = 0;
        foreach (i; locs)
        {
            if (nums.length == 0 || nums[$ - 1] < i.line)
            {
                nums ~= i.line;
                ml = max(ml, i.line.to!string.length);
            }
        }
        string ret;
        foreach (i; nums)
        {
            string s = i.to!string;
            foreach (j; 0 .. ml - s.length)
            {
                ret ~= ' ';
            }
            if (i > 0 && i < lines.length)
            {
                ret ~= i.to!string ~ ": " ~ lines[i - 1].to!string ~ "\n";
            }
        }
        e.msg = ret ~ e.msg;
        throw e;
    }
}

alias parseCached = memoize!parseUncached;

/// parses code as archive of the paka programming language
Node parseUncached(SrcLoc loc)
{
    SrcLoc[] olocs = locs;
    locs = null;
    staticCtx ~= Context.base;
    scope (exit)
    {
        locs = olocs;
        staticCtx.length--;
    }
    fileSystem ~= parseHar(loc, fileSystem);
    MemoryTextFile main = "main.paka".readMemFile;
    if (main is null)
    {
        main = "__main__".readMemFile;
    }
    if (main is null)
    {
        throw new Exception("input error: missing __main__");
    }
    SrcLoc location = main.location;
    Node ret = location.parsePaka;
    return ret;
}

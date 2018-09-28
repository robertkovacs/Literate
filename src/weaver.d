// src/weaver.d
// Weaver imports
import globals;
import std.process;
import std.file;
import std.conv;
import std.algorithm;
import std.regex;
import std.path;
import std.stdio;
import std.string;
import parser;
import util;
import dmarkdown;


void weave(Program p) 
{
    // Parse use locations
    string[string] defLocations;
    string[][string] redefLocations;
    string[][string] addLocations;
    string[][string] useLocations;
    
    foreach (chapter; p.chapters) 
    {
        foreach (s; chapter.sections) 
        {
            foreach (block; s.blocks) 
            {
                if (block.isCodeblock) 
                {
                    if (block.modifiers.canFind(Modifier.noWeave)) 
                    {
                        defLocations[block.name] = "noWeave";
                        continue;
                    }
    
                    // Check if it's a root block
                    auto fileMatch = matchAll(block.name, regex(".*\\.\\w+"));
                    auto quoteMatch = matchAll(block.name, regex("^\".*\"$"));
                    if (fileMatch || quoteMatch) 
                    {
                        block.isRootBlock = true;
                        if (quoteMatch) block.name = block.name[1..$-1];  
                    }

    
                    if (block.modifiers.canFind(Modifier.additive)) 
                    {
                        if (block.name !in addLocations || !addLocations[block.name].canFind(s.numToString()))
                        {
                            addLocations[block.name] ~= chapter.num() ~ ":" ~ s.numToString();
                        }
                    } 
                    else if (block.modifiers.canFind(Modifier.redef)) 
                    {
                        if (block.name !in redefLocations || !redefLocations[block.name].canFind(s.numToString()))
                        {
                            redefLocations[block.name] ~= chapter.num() ~ ":" ~ s.numToString();
                        }
                    } 
                    else 
                    {
                        defLocations[block.name] = chapter.num() ~ ":" ~ s.numToString();
                    }
    
                    foreach (lineObj; block.lines) 
                    {
                        string line = strip(lineObj.text);
                        if (line.startsWith("@{") && line.endsWith("}")) 
                        {
                            useLocations[line[2..$ - 1]] ~= chapter.num() ~ ":" ~ s.numToString();
                        }
                    }
                }
            }
        }
    }

    // Run weaveChapter
    foreach (c; p.chapters) 
    {
        string output = weaveChapter(c, p, defLocations, redefLocations,
                                     addLocations, useLocations);
        if (!noOutput) 
        {
            string dir = outDir;
            if (isBook) 
            {
                dir = outDir ~ "/_book";
                if (!dir.exists()) mkdir(dir);
            }
            File f = File(dir ~ "/" ~ stripExtension(baseName(c.file)) ~ ".html", "w");
            f.write(output);
            f.close();
        }
    }

    if (isBook && !noOutput) 
    {
// Create the table of contents
string dir = outDir ~ "/_book";
File f = File(dir ~ "/" ~ p.title ~ "_contents.html", "w");

f.writeln(
q"DELIMITER
<!DOCTYPE html>
<html>
<head>
</head>
<body>
<div class="container">
DELIMITER"
);

f.writeln("<h1>" ~ p.title ~ "</h1>");

string html;
string md = p.text;
if (useMdCompiler) 
{
    auto pipes = pipeShell(mdCompilerCmd, Redirect.stdin | Redirect.stdout | Redirect.stderrToStdout);
    pipes.stdin.write(md);
    pipes.stdin.flush();
    pipes.stdin.close();
    auto status = wait(pipes.pid);
    string mdCompilerOutput;
    foreach (line; pipes.stdout.byLine) mdCompilerOutput ~= line.idup;
    if (status != 0) 
    {
        warn(p.file, 1, "Custom markdown compilation failed: " ~ mdCompilerOutput ~ " -- Falling back to built-in markdown compiler");
        html = filterMarkdown(md, MarkdownFlags.backtickCodeBlocks);
        useMdCompiler = false;
    } 
    else 
    {
        html = mdCompilerOutput;
    }
} 
else 
{
    html = filterMarkdown(md, MarkdownFlags.backtickCodeBlocks);
}

f.writeln(html);

f.writeln("<ul id=\"contents\">");
foreach (c; p.chapters) 
{
    f.writeln("<li>" ~ c.num() ~ ". <a href=\"" ~ stripExtension(baseName(c.file)) ~ ".html\">" ~ c.title ~ "</a></li>");
}

f.writeln("
</ul>
</div>
</body>
");

f.close();


    }
}

// WeaveChapter
string weaveChapter(Chapter c, Program p, string[string] defLocations,
                    string[][string] redefLocations, string[][string] addLocations,
                    string[][string] useLocations) 
{
// prettify
string prettify = q"DELIMITER
! function ()
{
	var q = null;
	window.PR_SHOULD_USE_CONTINUATION = !0;
	(function ()
	{
		function R(a)
		{
			function d(e)
			{
				var b = e.charCodeAt(0);
				if (b !== 92) return b;
				var a = e.charAt(1);
				return (b = r[a]) ? b : "0" <= a && a <= "7" ? parseInt(e.substring(1), 8) : a === "u" || a === "x" ? parseInt(e.substring(2), 16) : e.charCodeAt(1)
			}

			function g(e)
			{
				if (e < 32) return (e < 16 ? "\\x0" : "\\x") + e.toString(16);
				e = String.fromCharCode(e);
				return e === "\\" || e === "-" || e === "]" || e === "^" ? "\\" + e : e
			}

			function b(e)
			{
				var b = e.substring(1, e.length - 1).match(/\\u[\dA-Fa-f]{4}|\\x[\dA-Fa-f]{2}|\\[0-3][0-7]{0,2}|\\[0-7]{1,2}|\\[\S\s]|[^\\]/g),
					e = [],
					a =
					b[0] === "^",
					c = ["["];
				a && c.push("^");
				for (var a = a ? 1 : 0, f = b.length; a < f; ++a)
				{
					var h = b[a];
					if (/\\[bdsw]/i.test(h)) c.push(h);
					else
					{
						var h = d(h),
							l;
						a + 2 < f && "-" === b[a + 1] ? (l = d(b[a + 2]), a += 2) : l = h;
						e.push([h, l]);
						l < 65 || h > 122 || (l < 65 || h > 90 || e.push([Math.max(65, h) | 32, Math.min(l, 90) | 32]), l < 97 || h > 122 || e.push([Math.max(97, h) & -33, Math.min(l, 122) & -33]))
					}
				}
				e.sort(function (e, a)
				{
					return e[0] - a[0] || a[1] - e[1]
				});
				b = [];
				f = [];
				for (a = 0; a < e.length; ++a) h = e[a], h[0] <= f[1] + 1 ? f[1] = Math.max(f[1], h[1]) : b.push(f = h);
				for (a = 0; a < b.length; ++a) h = b[a], c.push(g(h[0])),
					h[1] > h[0] && (h[1] + 1 > h[0] && c.push("-"), c.push(g(h[1])));
				c.push("]");
				return c.join("")
			}

			function s(e)
			{
				for (var a = e.source.match(/\[(?:[^\\\] ]|\\[\S\s])*]|\\u[\dA-Fa-f]{4}|\\x[\dA-Fa-f]{2}|\\\d+|\\[^\dux]|\(\?[!:=]|[()^]|[^()[\\^]+/g), c = a.length, d = [], f = 0, h = 0; f < c; ++f)
				{
					var l = a[f];
					l === "(" ? ++h : "\\" === l.charAt(0) && (l = +l.substring(1)) && (l <= h ? d[l] = -1 : a[f] = g(l))
				}
				for (f = 1; f < d.length; ++f) - 1 === d[f] && (d[f] = ++x);
				for (h = f = 0; f < c; ++f) l = a[f], l === "(" ? (++h, d[h] || (a[f] = "(?:")) : "\\" === l.charAt(0) && (l = +l.substring(1)) && l <= h &&
					(a[f] = "\\" + d[l]);
				for (f = 0; f < c; ++f) "^" === a[f] && "^" !== a[f + 1] && (a[f] = "");
				if (e.ignoreCase && m)
					for (f = 0; f < c; ++f) l = a[f], e = l.charAt(0), l.length >= 2 && e === "[" ? a[f] = b(l) : e !== "\\" && (a[f] = l.replace(/[A-Za-z]/g, function (a)
					{
						a = a.charCodeAt(0);
						return "[" + String.fromCharCode(a & -33, a | 32) + "]"
					}));
				return a.join("")
			}
			for (var x = 0, m = !1, j = !1, k = 0, c = a.length; k < c; ++k)
			{
				var i = a[k];
				if (i.ignoreCase) j = !0;
				else if (/[a-z]/i.test(i.source.replace(/\\u[\da-f]{4}|\\x[\da-f]{2}|\\[^UXux]/gi, "")))
				{
					m = !0;
					j = !1;
					break
				}
			}
			for (var r = {
					b: 8,
					t: 9,
					n: 10,
					v: 11,
					f: 12,
					r: 13
				}, n = [], k = 0, c = a.length; k < c; ++k)
			{
				i = a[k];
				if (i.global || i.multiline) throw Error("" + i);
				n.push("(?:" + s(i) + ")")
			}
			return RegExp(n.join("|"), j ? "gi" : "g")
		}

		function S(a, d)
		{
			function g(a)
			{
				var c = a.nodeType;
				if (c == 1)
				{
					if (!b.test(a.className))
					{
						for (c = a.firstChild; c; c = c.nextSibling) g(c);
						c = a.nodeName.toLowerCase();
						if ("br" === c || "li" === c) s[j] = "\n", m[j << 1] = x++, m[j++ << 1 | 1] = a
					}
				}
				else if (c == 3 || c == 4) c = a.nodeValue, c.length && (c = d ? c.replace(/\r\n?/g, "\n") : c.replace(/[\t\n\r ]+/g, " "), s[j] = c, m[j << 1] = x, x += c.length, m[j++ << 1 | 1] =
					a)
			}
			var b = /(?:^|\s)nocode(?:\s|$)/,
				s = [],
				x = 0,
				m = [],
				j = 0;
			g(a);
			return {
				a: s.join("").replace(/\n$/, ""),
				d: m
			}
		}

		function H(a, d, g, b)
		{
			d && (a = {
				a: d,
				e: a
			}, g(a), b.push.apply(b, a.g))
		}

		function T(a)
		{
			for (var d = void 0, g = a.firstChild; g; g = g.nextSibling) var b = g.nodeType,
				d = b === 1 ? d ? a : g : b === 3 ? U.test(g.nodeValue) ? a : d : d;
			return d === a ? void 0 : d
		}

		function D(a, d)
		{
			function g(a)
			{
				for (var j = a.e, k = [j, "pln"], c = 0, i = a.a.match(s) || [], r = {}, n = 0, e = i.length; n < e; ++n)
				{
					var z = i[n],
						w = r[z],
						t = void 0,
						f;
					if (typeof w === "string") f = !1;
					else
					{
						var h = b[z.charAt(0)];
						if (h) t = z.match(h[1]), w = h[0];
						else
						{
							for (f = 0; f < x; ++f)
								if (h = d[f], t = z.match(h[1]))
								{
									w = h[0];
									break
								}
							t || (w = "pln")
						}
						if ((f = w.length >= 5 && "lang-" === w.substring(0, 5)) && !(t && typeof t[1] === "string")) f = !1, w = "src";
						f || (r[z] = w)
					}
					h = c;
					c += z.length;
					if (f)
					{
						f = t[1];
						var l = z.indexOf(f),
							B = l + f.length;
						t[2] && (B = z.length - t[2].length, l = B - f.length);
						w = w.substring(5);
						H(j + h, z.substring(0, l), g, k);
						H(j + h + l, f, I(w, f), k);
						H(j + h + B, z.substring(B), g, k)
					}
					else k.push(j + h, w)
				}
				a.g = k
			}
			var b = {},
				s;
			(function ()
			{
				for (var g = a.concat(d), j = [], k = {}, c = 0, i = g.length; c < i; ++c)
				{
					var r =
						g[c],
						n = r[3];
					if (n)
						for (var e = n.length; --e >= 0;) b[n.charAt(e)] = r;
					r = r[1];
					n = "" + r;
					k.hasOwnProperty(n) || (j.push(r), k[n] = q)
				}
				j.push(/[\S\s]/);
				s = R(j)
			})();
			var x = d.length;
			return g
		}

		function v(a)
		{
			var d = [],
				g = [];
			a.tripleQuotedStrings ? d.push(["str", /^(?:'''(?:[^'\\]|\\[\S\s]|''?(?=[^']))*(?:'''|$)|"""(?:[^"\\]|\\[\S\s]|""?(?=[^"]))*(?:"""|$)|'(?:[^'\\]|\\[\S\s])*(?:'|$)|"(?:[^"\\]|\\[\S\s])*(?:"|$))/, q, "'\""]) : a.multiLineStrings ? d.push(["str", /^(?:'(?:[^'\\]|\\[\S\s])*(?:'|$)|"(?:[^"\\]|\\[\S\s])*(?:"|$)|`(?:[^\\`]|\\[\S\s])*(?:`|$))/,
				q, "'\"`"
			]) : d.push(["str", /^(?:'(?:[^\n\r'\\]|\\.)*(?:'|$)|"(?:[^\n\r"\\]|\\.)*(?:"|$))/, q, "\"'"]);
			a.verbatimStrings && g.push(["str", /^@"(?:[^"]|"")*(?:"|$)/, q]);
			var b = a.hashComments;
			b && (a.cStyleComments ? (b > 1 ? d.push(["com", /^#(?:##(?:[^#]|#(?!##))*(?:###|$)|.*)/, q, "#"]) : d.push(["com", /^#(?:(?:define|e(?:l|nd)if|else|error|ifn?def|include|line|pragma|undef|warning)\b|[^\n\r]*)/, q, "#"]), g.push(["str", /^<(?:(?:(?:\.\.\/)*|\/?)(?:[\w-]+(?:\/[\w-]+)+)?[\w-]+\.h(?:h|pp|\+\+)?|[a-z]\w*)>/, q])) : d.push(["com",
				/^#[^\n\r]*/, q, "#"
			]));
			a.cStyleComments && (g.push(["com", /^\/\/[^\n\r]*/, q]), g.push(["com", /^\/\*[\S\s]*?(?:\*\/|$)/, q]));
			if (b = a.regexLiterals)
			{
				var s = (b = b > 1 ? "" : "\n\r") ? "." : "[\\S\\s]";
				g.push(["lang-regex", RegExp("^(?:^^\\.?|[+-]|[!=]=?=?|\\#|%=?|&&?=?|\\(|\\*=?|[+\\-]=|->|\\/=?|::?|<<?=?|>>?>?=?|,|;|\\?|@|\\[|~|{|\\^\\^?=?|\\|\\|?=?|break|case|continue|delete|do|else|finally|instanceof|return|throw|try|typeof)\\s*(" + ("/(?=[^/*" + b + "])(?:[^/\\x5B\\x5C" + b + "]|\\x5C" + s + "|\\x5B(?:[^\\x5C\\x5D" + b + "]|\\x5C" +
					s + ")*(?:\\x5D|$))+/") + ")")])
			}(b = a.types) && g.push(["typ", b]);
			b = ("" + a.keywords).replace(/^ | $/g, "");
			b.length && g.push(["kwd", RegExp("^(?:" + b.replace(/[\s,]+/g, "|") + ")\\b"), q]);
			d.push(["pln", /^\s+/, q, " \r\n\t "]);
			b = "^.[^\\s\\w.$@'\"`/\\\\]*";
			a.regexLiterals && (b += "(?!s*/)");
			g.push(["lit", /^@[$_a-z][\w$@]*/i, q], ["typ", /^(?:[@_]?[A-Z]+[a-z][\w$@]*|\w+_t\b)/, q], ["pln", /^[$_a-z][\w$@]*/i, q], ["lit", /^(?:0x[\da-f]+|(?:\d(?:_\d+)*\d*(?:\.\d*)?|\.\d\+)(?:e[+-]?\d+)?)[a-z]*/i, q, "0123456789"], ["pln", /^\\[\S\s]?/,
				q
			], ["pun", RegExp(b), q]);
			return D(d, g)
		}

		function J(a, d, g)
		{
			function b(a)
			{
				var c = a.nodeType;
				if (c == 1 && !x.test(a.className))
					if ("br" === a.nodeName) s(a), a.parentNode && a.parentNode.removeChild(a);
					else
						for (a = a.firstChild; a; a = a.nextSibling) b(a);
				else if ((c == 3 || c == 4) && g)
				{
					var d = a.nodeValue,
						i = d.match(m);
					if (i) c = d.substring(0, i.index), a.nodeValue = c, (d = d.substring(i.index + i[0].length)) && a.parentNode.insertBefore(j.createTextNode(d), a.nextSibling), s(a), c || a.parentNode.removeChild(a)
				}
			}

			function s(a)
			{
				function b(a, c)
				{
					var d =
						c ? a.cloneNode(!1) : a,
						e = a.parentNode;
					if (e)
					{
						var e = b(e, 1),
							g = a.nextSibling;
						e.appendChild(d);
						for (var i = g; i; i = g) g = i.nextSibling, e.appendChild(i)
					}
					return d
				}
				for (; !a.nextSibling;)
					if (a = a.parentNode, !a) return;
				for (var a = b(a.nextSibling, 0), d;
					(d = a.parentNode) && d.nodeType === 1;) a = d;
				c.push(a)
			}
			for (var x = /(?:^|\s)nocode(?:\s|$)/, m = /\r\n?|\n/, j = a.ownerDocument, k = j.createElement("li"); a.firstChild;) k.appendChild(a.firstChild);
			for (var c = [k], i = 0; i < c.length; ++i) b(c[i]);
			d === (d | 0) && c[0].setAttribute("value", d);
			var r = j.createElement("ol");
			r.className = "linenums";
			for (var d = Math.max(0, d - 1 | 0) || 0, i = 0, n = c.length; i < n; ++i) k = c[i], k.className = "L" + (i + d) % 10, k.firstChild || k.appendChild(j.createTextNode(" ")), r.appendChild(k);
			a.appendChild(r)
		}

		function p(a, d)
		{
			for (var g = d.length; --g >= 0;)
			{
				var b = d[g];
				F.hasOwnProperty(b) ? E.console && console.warn("cannot override language handler %s", b) : F[b] = a
			}
		}

		function I(a, d)
		{
			if (!a || !F.hasOwnProperty(a)) a = /^\s*</.test(d) ? "default-markup" : "default-code";
			return F[a]
		}

		function K(a)
		{
			var d = a.h;
			try
			{
				var g = S(a.c, a.i),
					b = g.a;
				a.a = b;
				a.d = g.d;
				a.e = 0;
				I(d, b)(a);
				var s = /\bMSIE\s(\d+)/.exec(navigator.userAgent),
					s = s && +s[1] <= 8,
					d = /\n/g,
					x = a.a,
					m = x.length,
					g = 0,
					j = a.d,
					k = j.length,
					b = 0,
					c = a.g,
					i = c.length,
					r = 0;
				c[i] = m;
				var n, e;
				for (e = n = 0; e < i;) c[e] !== c[e + 2] ? (c[n++] = c[e++], c[n++] = c[e++]) : e += 2;
				i = n;
				for (e = n = 0; e < i;)
				{
					for (var p = c[e], w = c[e + 1], t = e + 2; t + 2 <= i && c[t + 1] === w;) t += 2;
					c[n++] = p;
					c[n++] = w;
					e = t
				}
				c.length = n;
				var f = a.c,
					h;
				if (f) h = f.style.display, f.style.display = "none";
				try
				{
					for (; b < k;)
					{
						var l = j[b + 2] || m,
							B = c[r + 2] || m,
							t = Math.min(l, B),
							A = j[b + 1],
							G;
						if (A.nodeType !== 1 && (G = x.substring(g,
								t)))
						{
							s && (G = G.replace(d, "\r"));
							A.nodeValue = G;
							var L = A.ownerDocument,
								o = L.createElement("span");
							o.className = c[r + 1];
							var v = A.parentNode;
							v.replaceChild(o, A);
							o.appendChild(A);
							g < l && (j[b + 1] = A = L.createTextNode(x.substring(t, l)), v.insertBefore(A, o.nextSibling))
						}
						g = t;
						g >= l && (b += 2);
						g >= B && (r += 2)
					}
				}
				finally
				{
					if (f) f.style.display = h
				}
			}
			catch (u)
			{
				E.console && console.log(u && u.stack || u)
			}
		}
		var E = window,
			y = ["break,continue,do,else,for,if,return,while"],
			C = [
				[y, "auto,case,char,const,default,double,enum,extern,float,goto,inline,int,long,register,short,signed,sizeof,static,struct,switch,typedef,union,unsigned,void,volatile"],
				"catch,class,delete,false,import,new,operator,private,protected,public,this,throw,true,try,typeof"
			],
			M = [C, "alignof,align_union,asm,axiom,bool,concept,concept_map,const_cast,constexpr,decltype,delegate,dynamic_cast,explicit,export,friend,generic,late_check,mutable,namespace,nullptr,property,reinterpret_cast,static_assert,static_cast,template,typeid,typename,using,virtual,where"],
			V = [C, "abstract,assert,boolean,byte,extends,final,finally,implements,import,instanceof,interface,null,native,package,strictfp,super,synchronized,throws,transient"],
			N = [C, "abstract,as,base,bool,by,byte,checked,decimal,delegate,descending,dynamic,event,finally,fixed,foreach,from,group,implicit,in,interface,internal,into,is,let,lock,null,object,out,override,orderby,params,partial,readonly,ref,sbyte,sealed,stackalloc,string,select,uint,ulong,unchecked,unsafe,ushort,var,virtual,where"],
			C = [C, "debugger,eval,export,function,get,null,set,undefined,var,with,Infinity,NaN"],
			O = [y, "and,as,assert,class,def,del,elif,except,exec,finally,from,global,import,in,is,lambda,nonlocal,not,or,pass,print,raise,try,with,yield,False,True,None"],
			P = [y, "alias,and,begin,case,class,def,defined,elsif,end,ensure,false,in,module,next,nil,not,or,redo,rescue,retry,self,super,then,true,undef,unless,until,when,yield,BEGIN,END"],
			W = [y, "as,assert,const,copy,drop,enum,extern,fail,false,fn,impl,let,log,loop,match,mod,move,mut,priv,pub,pure,ref,self,static,struct,true,trait,type,unsafe,use"],
			y = [y, "case,done,elif,esac,eval,fi,function,in,local,set,then,until"],
			Q = /^(DIR|FILE|vector|(de|priority_)?queue|list|stack|(const_)?iterator|(multi)?(set|map)|bitset|u?(int|float)\d*)\b/,
			U = /\S/,
			X = v(
			{
				keywords: [M, N, C, "caller,delete,die,do,dump,elsif,eval,exit,foreach,for,goto,if,import,last,local,my,next,no,our,print,package,redo,require,sub,undef,unless,until,use,wantarray,while,BEGIN,END", O, P, y],
				hashComments: !0,
				cStyleComments: !0,
				multiLineStrings: !0,
				regexLiterals: !0
			}),
			F = {};
		p(X, ["default-code"]);
		p(D([], [
			["pln", /^[^<?]+/],
			["dec", /^<!\w[^>]*(?:>|$)/],
			["com", /^<\!--[\S\s]*?(?:--\>|$)/],
			["lang-", /^<\?([\S\s]+?)(?:\?>|$)/],
			["lang-", /^<%([\S\s]+?)(?:%>|$)/],
			["pun", /^(?:<[%?]|[%?]>)/],
			["lang-",
				/^<xmp\b[^>]*>([\S\s]+?)<\/xmp\b[^>]*>/i
			],
			["lang-js", /^<script\b[^>]*>([\S\s]*?)(<\/script\b[^>]*>)/i],
			["lang-css", /^<style\b[^>]*>([\S\s]*?)(<\/style\b[^>]*>)/i],
			["lang-in.tag", /^(<\/?[a-z][^<>]*>)/i]
		]), ["default-markup", "htm", "html", "mxml", "xhtml", "xml", "xsl"]);
		p(D([
			["pln", /^\s+/, q, " \t\r\n"],
			["atv", /^(?:"[^"]*"?|'[^']*'?)/, q, "\"'"]
		], [
			["tag", /^^<\/?[a-z](?:[\w-.:]*\w)?|\/?>$/i],
			["atn", /^(?!style[\s=]|on)[a-z](?:[\w:-]*\w)?/i],
			["lang-uq.val", /^=\s*([^\s"'>]*(?:[^\s"'/>]|\/(?=\s)))/],
			["pun", /^[/<->]+/],
			["lang-js", /^on\w+\s*=\s*"([^"]+)"/i],
			["lang-js", /^on\w+\s*=\s*'([^']+)'/i],
			["lang-js", /^on\w+\s*=\s*([^\s"'>]+)/i],
			["lang-css", /^style\s*=\s*"([^"]+)"/i],
			["lang-css", /^style\s*=\s*'([^']+)'/i],
			["lang-css", /^style\s*=\s*([^\s"'>]+)/i]
		]), ["in.tag"]);
		p(D([], [
			["atv", /^[\S\s]+/]
		]), ["uq.val"]);
		p(v(
		{
			keywords: M,
			hashComments: !0,
			cStyleComments: !0,
			types: Q
		}), ["c", "cc", "cpp", "cxx", "cyc", "m"]);
		p(v(
		{
			keywords: "null,true,false"
		}), ["json"]);
		p(v(
		{
			keywords: N,
			hashComments: !0,
			cStyleComments: !0,
			verbatimStrings: !0,
			types: Q
		}), ["cs"]);
		p(v(
		{
			keywords: V,
			cStyleComments: !0
		}), ["java"]);
		p(v(
		{
			keywords: y,
			hashComments: !0,
			multiLineStrings: !0
		}), ["bash", "bsh", "csh", "sh"]);
		p(v(
		{
			keywords: O,
			hashComments: !0,
			multiLineStrings: !0,
			tripleQuotedStrings: !0
		}), ["cv", "py", "python"]);
		p(v(
		{
			keywords: "caller,delete,die,do,dump,elsif,eval,exit,foreach,for,goto,if,import,last,local,my,next,no,our,print,package,redo,require,sub,undef,unless,until,use,wantarray,while,BEGIN,END",
			hashComments: !0,
			multiLineStrings: !0,
			regexLiterals: 2
		}), ["perl", "pl", "pm"]);
		p(v(
		{
			keywords: P,
			hashComments: !0,
			multiLineStrings: !0,
			regexLiterals: !0
		}), ["rb", "ruby"]);
		p(v(
		{
			keywords: C,
			cStyleComments: !0,
			regexLiterals: !0
		}), ["javascript", "js"]);
		p(v(
		{
			keywords: "all,and,by,catch,class,else,extends,false,finally,for,if,in,is,isnt,loop,new,no,not,null,of,off,on,or,return,super,then,throw,true,try,unless,until,when,while,yes",
			hashComments: 3,
			cStyleComments: !0,
			multilineStrings: !0,
			tripleQuotedStrings: !0,
			regexLiterals: !0
		}), ["coffee"]);
		p(v(
		{
			keywords: W,
			cStyleComments: !0,
			multilineStrings: !0
		}), ["rc", "rs", "rust"]);
		p(D([], [
			["str", /^[\S\s]+/]
		]), ["regex"]);
		var Y = E.PR = {
			createSimpleLexer: D,
			registerLangHandler: p,
			sourceDecorator: v,
			PR_ATTRIB_NAME: "atn",
			PR_ATTRIB_VALUE: "atv",
			PR_COMMENT: "com",
			PR_DECLARATION: "dec",
			PR_KEYWORD: "kwd",
			PR_LITERAL: "lit",
			PR_NOCODE: "nocode",
			PR_PLAIN: "pln",
			PR_PUNCTUATION: "pun",
			PR_SOURCE: "src",
			PR_STRING: "str",
			PR_TAG: "tag",
			PR_TYPE: "typ",
			prettyPrintOne: E.prettyPrintOne = function (a, d, g)
			{
				var b = document.createElement("div");
				b.innerHTML = "<pre>" + a + "</pre>";
				b = b.firstChild;
				g && J(b, g, !0);
				K(
				{
					h: d,
					j: g,
					c: b,
					i: 1
				});
				return b.innerHTML
			},
			prettyPrint: E.prettyPrint = function (a, d)
			{
				function g()
				{
					for (var b = E.PR_SHOULD_USE_CONTINUATION ? c.now() + 250 : Infinity; i < p.length && c.now() < b; i++)
					{
						for (var d = p[i], j = h, k = d; k = k.previousSibling;)
						{
							var m = k.nodeType,
								o = (m === 7 || m === 8) && k.nodeValue;
							if (o ? !/^\??prettify\b/.test(o) : m !== 3 || /\S/.test(k.nodeValue)) break;
							if (o)
							{
								j = {};
								o.replace(/\b(\w+)=([\w%+\-.:]+)/g, function (a, b, c)
								{
									j[b] = c
								});
								break
							}
						}
						k = d.className;
						if ((j !== h || e.test(k)) && !v.test(k))
						{
							m = !1;
							for (o = d.parentNode; o; o = o.parentNode)
								if (f.test(o.tagName) &&
									o.className && e.test(o.className))
								{
									m = !0;
									break
								}
							if (!m)
							{
								d.className += " prettyprinted";
								m = j.lang;
								if (!m)
								{
									var m = k.match(n),
										y;
									if (!m && (y = T(d)) && t.test(y.tagName)) m = y.className.match(n);
									m && (m = m[1])
								}
								if (w.test(d.tagName)) o = 1;
								else var o = d.currentStyle,
									u = s.defaultView,
									o = (o = o ? o.whiteSpace : u && u.getComputedStyle ? u.getComputedStyle(d, q).getPropertyValue("white-space") : 0) && "pre" === o.substring(0, 3);
								u = j.linenums;
								if (!(u = u === "true" || +u)) u = (u = k.match(/\blinenums\b(?::(\d+))?/)) ? u[1] && u[1].length ? +u[1] : !0 : !1;
								u && J(d, u, o);
								r = {
									h: m,
									c: d,
									j: u,
									i: o
								};
								K(r)
							}
						}
					}
					i < p.length ? setTimeout(g, 250) : "function" === typeof a && a()
				}
				for (var b = d || document.body, s = b.ownerDocument || document, b = [b.getElementsByTagName("pre"), b.getElementsByTagName("code"), b.getElementsByTagName("xmp")], p = [], m = 0; m < b.length; ++m)
					for (var j = 0, k = b[m].length; j < k; ++j)
						p.push(b[m][j]);
				var b = q,
					c = Date;
				c.now || (c = {
					now: function ()
					{
						return +new Date
					}
				});
				var i = 0,
					r, n = /\blang(?:uage)?-([\w.]+)(?!\S)/,
					e = /\bprettyprint\b/,
					v = /\bprettyprinted\b/,
					w = /pre|xmp/i,
					t = /^code$/i,
					f = /^(?:pre|code|xmp)$/i,
					h = {};
				g()
			}
		};
		typeof define === "function" && define.amd && define("google-code-prettify", [], function ()
		{
			return Y
		})
	})();
}()
DELIMITER";

string[string] extensions;

string lisp = q"DELIMITER
PR.registerLangHandler(PR.createSimpleLexer([["opn",/^\(+/,null,"("],["clo",/^\)+/,null,")"],[PR.PR_COMMENT,/^;[^\r\n]*/,null,";"],[PR.PR_PLAIN,/^[\t\n\r \xA0]+/,null,"    \n\r  "],[PR.PR_STRING,/^\"(?:[^\"\\]|\\[\s\S])*(?:\"|$)/,null,'"']],[[PR.PR_KEYWORD,/^(?:block|c[ad]+r|catch|con[ds]|def(?:ine|un)|do|eq|eql|equal|equalp|eval-when|flet|format|go|if|labels|lambda|let|load-time-value|locally|macrolet|multiple-value-call|nil|progn|progv|quote|require|return-from|setq|symbol-macrolet|t|tagbody|the|throw|unwind)\b/,null],[PR.PR_LITERAL,/^[+\-]?(?:[0#]x[0-9a-f]+|\d+\/\d+|(?:\.\d+|\d+(?:\.\d*)?)(?:[ed][+\-]?\d+)?)/i],[PR.PR_LITERAL,/^\'(?:-*(?:\w|\\[\x21-\x7e])(?:[\w-]*|\\[\x21-\x7e])[=!?]?)?/],[PR.PR_PLAIN,/^-*(?:[a-z_]|\\[\x21-\x7e])(?:[\w-]*|\\[\x21-\x7e])[=!?]?/i],[PR.PR_PUNCTUATION,/^[^\w\t\n\r \xA0()\"\\\';]+/]]),["cl","el","lisp","lsp","scm","ss","rkt"]);
DELIMITER";
extensions["cl"] = lisp;
extensions["el"] = lisp;
extensions["lisp"] = lisp;
extensions["lsp"] = lisp;
extensions["scm"] = lisp;
extensions["ss"] = lisp;
extensions["rkt"] = lisp;
string clojure = q"DELIMITER
PR.registerLangHandler(PR.createSimpleLexer([["opn",/^[\(\{\[]+/,null,"([{"],["clo",/^[\)\}\]]+/,null,")]}"],[PR.PR_COMMENT,/^;[^\r\n]*/,null,";"],[PR.PR_PLAIN,/^[\t\n\r \xA0]+/,null,"    \n\r  "],[PR.PR_STRING,/^\"(?:[^\"\\]|\\[\s\S])*(?:\"|$)/,null,'"']],[[PR.PR_KEYWORD,/^(?:def|if|do|let|quote|var|fn|loop|recur|throw|try|monitor-enter|monitor-exit|defmacro|defn|defn-|macroexpand|macroexpand-1|for|doseq|dosync|dotimes|and|or|when|not|assert|doto|proxy|defstruct|first|rest|cons|defprotocol|deftype|defrecord|reify|defmulti|defmethod|meta|with-meta|ns|in-ns|create-ns|import|intern|refer|alias|namespace|resolve|ref|deref|refset|new|set!|memfn|to-array|into-array|aset|gen-class|reduce|map|filter|find|nil?|empty?|hash-map|hash-set|vec|vector|seq|flatten|reverse|assoc|dissoc|list|list?|disj|get|union|difference|intersection|extend|extend-type|extend-protocol|prn)\b/,null],[PR.PR_TYPE,/^:[0-9a-zA-Z\-]+/]]),["clj"]);
DELIMITER";
extensions["clj"] = clojure;
string erlang = q"DELIMITER
PR.registerLangHandler(PR.createSimpleLexer([[PR.PR_PLAIN,/^[\t\n\x0B\x0C\r ]+/,null,"  \n\f\r "],[PR.PR_STRING,/^\"(?:[^\"\\\n\x0C\r]|\\[\s\S])*(?:\"|$)/,null,'"'],[PR.PR_LITERAL,/^[a-z][a-zA-Z0-9_]*/],[PR.PR_LITERAL,/^\'(?:[^\'\\\n\x0C\r]|\\[^&])+\'?/,null,"'"],[PR.PR_LITERAL,/^\?[^ \t\n({]+/,null,"?"],[PR.PR_LITERAL,/^(?:0o[0-7]+|0x[\da-f]+|\d+(?:\.\d+)?(?:e[+\-]?\d+)?)/i,null,"0123456789"]],[[PR.PR_COMMENT,/^%[^\n]*/],[PR.PR_KEYWORD,/^(?:module|attributes|do|let|in|letrec|apply|call|primop|case|of|end|when|fun|try|catch|receive|after|char|integer|float,atom,string,var)\b/],[PR.PR_KEYWORD,/^-[a-z_]+/],[PR.PR_TYPE,/^[A-Z_][a-zA-Z0-9_]*/],[PR.PR_PUNCTUATION,/^[.,;]/]]),["erlang","erl"]);
DELIMITER";
extensions["erlang"] = erlang;
extensions["erl"] = erlang;
string go = q"DELIMITER
PR.registerLangHandler(PR.createSimpleLexer([[PR.PR_PLAIN,/^[\t\n\r \xA0]+/,null,"  \n\r  "],[PR.PR_PLAIN,/^(?:\"(?:[^\"\\]|\\[\s\S])*(?:\"|$)|\'(?:[^\'\\]|\\[\s\S])+(?:\'|$)|`[^`]*(?:`|$))/,null,"\"'"]],[[PR.PR_COMMENT,/^(?:\/\/[^\r\n]*|\/\*[\s\S]*?\*\/)/],[PR.PR_PLAIN,/^(?:[^\/\"\'`]|\/(?![\/\*]))+/i]]),["go"]);
DELIMITER";
extensions["go"] = go;
string rust = q"DELIMITER
PR.registerLangHandler(PR.createSimpleLexer([],[[PR.PR_PLAIN,/^[\t\n\r \xA0]+/],[PR.PR_COMMENT,/^\/\/.*/],[PR.PR_COMMENT,/^\/\*[\s\S]*?(?:\*\/|$)/],[PR.PR_STRING,/^b"(?:[^\\]|\\(?:.|x[\da-fA-F]{2}))*?"/],[PR.PR_STRING,/^"(?:[^\\]|\\(?:.|x[\da-fA-F]{2}|u\{\[\da-fA-F]{1,6}\}))*?"/],[PR.PR_STRING,/^b?r(#*)\"[\s\S]*?\"\1/],[PR.PR_STRING,/^b'([^\\]|\\(.|x[\da-fA-F]{2}))'/],[PR.PR_STRING,/^'([^\\]|\\(.|x[\da-fA-F]{2}|u\{[\da-fA-F]{1,6}\}))'/],[PR.PR_TAG,/^'\w+?\b/],[PR.PR_KEYWORD,/^(?:match|if|else|as|break|box|continue|extern|fn|for|in|if|impl|let|loop|pub|return|super|unsafe|where|while|use|mod|trait|struct|enum|type|move|mut|ref|static|const|crate)\b/],[PR.PR_KEYWORD,/^(?:alignof|become|do|offsetof|priv|pure|sizeof|typeof|unsized|yield|abstract|virtual|final|override|macro)\b/],[PR.PR_TYPE,/^(?:[iu](8|16|32|64|size)|char|bool|f32|f64|str|Self)\b/],[PR.PR_TYPE,/^(?:Copy|Send|Sized|Sync|Drop|Fn|FnMut|FnOnce|Box|ToOwned|Clone|PartialEq|PartialOrd|Eq|Ord|AsRef|AsMut|Into|From|Default|Iterator|Extend|IntoIterator|DoubleEndedIterator|ExactSizeIterator|Option|Some|None|Result|Ok|Err|SliceConcatExt|String|ToString|Vec)\b/],[PR.PR_LITERAL,/^(self|true|false|null)\b/],[PR.PR_LITERAL,/^\d[0-9_]*(?:[iu](?:size|8|16|32|64))?/],[PR.PR_LITERAL,/^0x[a-fA-F0-9_]+(?:[iu](?:size|8|16|32|64))?/],[PR.PR_LITERAL,/^0o[0-7_]+(?:[iu](?:size|8|16|32|64))?/],[PR.PR_LITERAL,/^0b[01_]+(?:[iu](?:size|8|16|32|64))?/],[PR.PR_LITERAL,/^\d[0-9_]*\.(?![^\s\d.])/],[PR.PR_LITERAL,/^\d[0-9_]*(?:\.\d[0-9_]*)(?:[eE][+-]?[0-9_]+)?(?:f32|f64)?/],[PR.PR_LITERAL,/^\d[0-9_]*(?:\.\d[0-9_]*)?(?:[eE][+-]?[0-9_]+)(?:f32|f64)?/],[PR.PR_LITERAL,/^\d[0-9_]*(?:\.\d[0-9_]*)?(?:[eE][+-]?[0-9_]+)?(?:f32|f64)/],[PR.PR_ATTRIB_NAME,/^[a-z_]\w*!/i],[PR.PR_PLAIN,/^[a-z_]\w*/i],[PR.PR_ATTRIB_VALUE,/^#!?\[[\s\S]*?\]/],[PR.PR_PUNCTUATION,/^[+\-\/*=^&|!<>%[\](){}?:.,;]/],[PR.PR_PLAIN,/./]]),["rs"]);
DELIMITER";
extensions["rs"] = rust;
string swift = q"DELIMITER
PR.registerLangHandler(PR.createSimpleLexer([[PR.PR_PLAIN,/^[ \n\r\t\v\f\0]+/,null," \n\r   \f\x00"],[PR.PR_STRING,/^"(?:[^"\\]|(?:\\.)|(?:\\\((?:[^"\\)]|\\.)*\)))*"/,null,'"']],[[PR.PR_LITERAL,/^(?:(?:0x[\da-fA-F][\da-fA-F_]*\.[\da-fA-F][\da-fA-F_]*[pP]?)|(?:\d[\d_]*\.\d[\d_]*[eE]?))[+-]?\d[\d_]*/,null],[PR.PR_LITERAL,/^-?(?:(?:0(?:(?:b[01][01_]*)|(?:o[0-7][0-7_]*)|(?:x[\da-fA-F][\da-fA-F_]*)))|(?:\d[\d_]*))/,null],[PR.PR_LITERAL,/^(?:true|false|nil)\b/,null],[PR.PR_KEYWORD,/^\b(?:__COLUMN__|__FILE__|__FUNCTION__|__LINE__|#available|#else|#elseif|#endif|#if|#line|arch|arm|arm64|associativity|as|break|case|catch|class|continue|convenience|default|defer|deinit|didSet|do|dynamic|dynamicType|else|enum|extension|fallthrough|final|for|func|get|guard|import|indirect|infix|init|inout|internal|i386|if|in|iOS|iOSApplicationExtension|is|lazy|left|let|mutating|none|nonmutating|operator|optional|OSX|OSXApplicationExtension|override|postfix|precedence|prefix|private|protocol|Protocol|public|required|rethrows|return|right|safe|self|set|static|struct|subscript|super|switch|throw|try|Type|typealias|unowned|unsafe|var|weak|watchOS|while|willSet|x86_64)\b/,null],[PR.PR_COMMENT,/^\/\/.*?[\n\r]/,null],[PR.PR_COMMENT,/^\/\*[\s\S]*?(?:\*\/|$)/,null],[PR.PR_PUNCTUATION,/^<<=|<=|<<|>>=|>=|>>|===|==|\.\.\.|&&=|\.\.<|!==|!=|&=|~=|~|\(|\)|\[|\]|{|}|@|#|;|\.|,|:|\|\|=|\?\?|\|\||&&|&\*|&\+|&-|&=|\+=|-=|\/=|\*=|\^=|%=|\|=|->|`|==|\+\+|--|\/|\+|!|\*|%|<|>|&|\||\^|\?|=|-|_/,null],[PR.PR_TYPE,/^\b(?:[@_]?[A-Z]+[a-z][A-Za-z_$@0-9]*|\w+_t\b)/,null]]),["swift"]);
DELIMITER";
extensions["swift"] = swift;
string haskell = q"DELIMITER
PR.registerLangHandler(PR.createSimpleLexer([[PR.PR_PLAIN,/^[\t\n\x0B\x0C\r ]+/,null,"  \n\f\r "],[PR.PR_STRING,/^\"(?:[^\"\\\n\x0C\r]|\\[\s\S])*(?:\"|$)/,null,'"'],[PR.PR_STRING,/^\'(?:[^\'\\\n\x0C\r]|\\[^&])\'?/,null,"'"],[PR.PR_LITERAL,/^(?:0o[0-7]+|0x[\da-f]+|\d+(?:\.\d+)?(?:e[+\-]?\d+)?)/i,null,"0123456789"]],[[PR.PR_COMMENT,/^(?:(?:--+(?:[^\r\n\x0C]*)?)|(?:\{-(?:[^-]|-+[^-\}])*-\}))/],[PR.PR_KEYWORD,/^(?:case|class|data|default|deriving|do|else|if|import|in|infix|infixl|infixr|instance|let|module|newtype|of|then|type|where|_)(?=[^a-zA-Z0-9\']|$)/,null],[PR.PR_PLAIN,/^(?:[A-Z][\w\']*\.)*[a-zA-Z][\w\']*/],[PR.PR_PUNCTUATION,/^[^\t\n\x0B\x0C\r a-zA-Z0-9\'\"]+/]]),["hs"]);
DELIMITER";
extensions["hs"] = haskell;
string matlab = q"DELIMITER
(function (PR) {
  /*
    PR_PLAIN: plain text
    PR_STRING: string literals
    PR_KEYWORD: keywords
    PR_COMMENT: comments
    PR_TYPE: types
    PR_LITERAL: literal values (1, null, true, ..)
    PR_PUNCTUATION: punctuation string
    PR_SOURCE: embedded source
    PR_DECLARATION: markup declaration such as a DOCTYPE
    PR_TAG: sgml tag
    PR_ATTRIB_NAME: sgml attribute name
    PR_ATTRIB_VALUE: sgml attribute value
  */
  var PR_IDENTIFIER = "ident",
    PR_CONSTANT = "const",
    PR_FUNCTION = "fun",
    PR_FUNCTION_TOOLBOX = "fun_tbx",
    PR_SYSCMD = "syscmd",
    PR_CODE_OUTPUT = "codeoutput",
    PR_ERROR = "err",
    PR_WARNING = "wrn",
    PR_TRANSPOSE = "transpose",
    PR_LINE_CONTINUATION = "linecont";

  // Refer to: http://www.mathworks.com/help/matlab/functionlist-alpha.html
  var coreFunctions = [
    'abs|accumarray|acos(?:d|h)?|acot(?:d|h)?|acsc(?:d|h)?|actxcontrol(?:list|select)?|actxGetRunningServer|actxserver|addlistener|addpath|addpref|addtodate|airy|align|alim|all|allchild|alpha|alphamap|amd|ancestor|and|angle|annotation|any|area|arrayfun|asec(?:d|h)?|asin(?:d|h)?|assert|assignin|atan(?:2|d|h)?|audiodevinfo|audioplayer|audiorecorder|aufinfo|auread|autumn|auwrite|avifile|aviinfo|aviread|axes|axis|balance|bar(?:3|3h|h)?|base2dec|beep|BeginInvoke|bench|bessel(?:h|i|j|k|y)|beta|betainc|betaincinv|betaln|bicg|bicgstab|bicgstabl|bin2dec|bitand|bitcmp|bitget|bitmax|bitnot|bitor|bitset|bitshift|bitxor|blanks|blkdiag|bone|box|brighten|brush|bsxfun|builddocsearchdb|builtin|bvp4c|bvp5c|bvpget|bvpinit|bvpset|bvpxtend|calendar|calllib|callSoapService|camdolly|cameratoolbar|camlight|camlookat|camorbit|campan|campos|camproj|camroll|camtarget|camup|camva|camzoom|cart2pol|cart2sph|cast|cat|caxis|cd|cdf2rdf|cdfepoch|cdfinfo|cdflib(?:\.(?:close|closeVar|computeEpoch|computeEpoch16|create|createAttr|createVar|delete|deleteAttr|deleteAttrEntry|deleteAttrgEntry|deleteVar|deleteVarRecords|epoch16Breakdown|epochBreakdown|getAttrEntry|getAttrgEntry|getAttrMaxEntry|getAttrMaxgEntry|getAttrName|getAttrNum|getAttrScope|getCacheSize|getChecksum|getCompression|getCompressionCacheSize|getConstantNames|getConstantValue|getCopyright|getFileBackward|getFormat|getLibraryCopyright|getLibraryVersion|getMajority|getName|getNumAttrEntries|getNumAttrgEntries|getNumAttributes|getNumgAttributes|getReadOnlyMode|getStageCacheSize|getValidate|getVarAllocRecords|getVarBlockingFactor|getVarCacheSize|getVarCompression|getVarData|getVarMaxAllocRecNum|getVarMaxWrittenRecNum|getVarName|getVarNum|getVarNumRecsWritten|getVarPadValue|getVarRecordData|getVarReservePercent|getVarsMaxWrittenRecNum|getVarSparseRecords|getVersion|hyperGetVarData|hyperPutVarData|inquire|inquireAttr|inquireAttrEntry|inquireAttrgEntry|inquireVar|open|putAttrEntry|putAttrgEntry|putVarData|putVarRecordData|renameAttr|renameVar|setCacheSize|setChecksum|setCompression|setCompressionCacheSize|setFileBackward|setFormat|setMajority|setReadOnlyMode|setStageCacheSize|setValidate|setVarAllocBlockRecords|setVarBlockingFactor|setVarCacheSize|setVarCompression|setVarInitialRecs|setVarPadValue|SetVarReservePercent|setVarsCacheSize|setVarSparseRecords))?|cdfread|cdfwrite|ceil|cell2mat|cell2struct|celldisp|cellfun|cellplot|cellstr|cgs|checkcode|checkin|checkout|chol|cholinc|cholupdate|circshift|cla|clabel|class|clc|clear|clearvars|clf|clipboard|clock|close|closereq|cmopts|cmpermute|cmunique|colamd|colon|colorbar|colordef|colormap|colormapeditor|colperm|Combine|comet|comet3|commandhistory|commandwindow|compan|compass|complex|computer|cond|condeig|condest|coneplot|conj|containers\.Map|contour(?:3|c|f|slice)?|contrast|conv|conv2|convhull|convhulln|convn|cool|copper|copyfile|copyobj|corrcoef|cos(?:d|h)?|cot(?:d|h)?|cov|cplxpair|cputime|createClassFromWsdl|createSoapMessage|cross|csc(?:d|h)?|csvread|csvwrite|ctranspose|cumprod|cumsum|cumtrapz|curl|customverctrl|cylinder|daqread|daspect|datacursormode|datatipinfo|date|datenum|datestr|datetick|datevec|dbclear|dbcont|dbdown|dblquad|dbmex|dbquit|dbstack|dbstatus|dbstep|dbstop|dbtype|dbup|dde23|ddeget|ddesd|ddeset|deal|deblank|dec2base|dec2bin|dec2hex|decic|deconv|del2|delaunay|delaunay3|delaunayn|DelaunayTri|delete|demo|depdir|depfun|det|detrend|deval|diag|dialog|diary|diff|diffuse|dir|disp|display|dither|divergence|dlmread|dlmwrite|dmperm|doc|docsearch|dos|dot|dragrect|drawnow|dsearch|dsearchn|dynamicprops|echo|echodemo|edit|eig|eigs|ellipj|ellipke|ellipsoid|empty|enableNETfromNetworkDrive|enableservice|EndInvoke|enumeration|eomday|eq|erf|erfc|erfcinv|erfcx|erfinv|error|errorbar|errordlg|etime|etree|etreeplot|eval|evalc|evalin|event\.(?:EventData|listener|PropertyEvent|proplistener)|exifread|exist|exit|exp|expint|expm|expm1|export2wsdlg|eye|ezcontour|ezcontourf|ezmesh|ezmeshc|ezplot|ezplot3|ezpolar|ezsurf|ezsurfc|factor|factorial|fclose|feather|feature|feof|ferror|feval|fft|fft2|fftn|fftshift|fftw|fgetl|fgets|fieldnames|figure|figurepalette|fileattrib|filebrowser|filemarker|fileparts|fileread|filesep|fill|fill3|filter|filter2|find|findall|findfigs|findobj|findstr|finish|fitsdisp|fitsinfo|fitsread|fitswrite|fix|flag|flipdim|fliplr|flipud|floor|flow|fminbnd|fminsearch|fopen|format|fplot|fprintf|frame2im|fread|freqspace|frewind|fscanf|fseek|ftell|FTP|full|fullfile|func2str|functions|funm|fwrite|fzero|gallery|gamma|gammainc|gammaincinv|gammaln|gca|gcbf|gcbo|gcd|gcf|gco|ge|genpath|genvarname|get|getappdata|getenv|getfield|getframe|getpixelposition|getpref|ginput|gmres|gplot|grabcode|gradient|gray|graymon|grid|griddata(?:3|n)?|griddedInterpolant|gsvd|gt|gtext|guidata|guide|guihandles|gunzip|gzip|h5create|h5disp|h5info|h5read|h5readatt|h5write|h5writeatt|hadamard|handle|hankel|hdf|hdf5|hdf5info|hdf5read|hdf5write|hdfinfo|hdfread|hdftool|help|helpbrowser|helpdesk|helpdlg|helpwin|hess|hex2dec|hex2num|hgexport|hggroup|hgload|hgsave|hgsetget|hgtransform|hidden|hilb|hist|histc|hold|home|horzcat|hostid|hot|hsv|hsv2rgb|hypot|ichol|idivide|ifft|ifft2|ifftn|ifftshift|ilu|im2frame|im2java|imag|image|imagesc|imapprox|imfinfo|imformats|import|importdata|imread|imwrite|ind2rgb|ind2sub|inferiorto|info|inline|inmem|inpolygon|input|inputdlg|inputname|inputParser|inspect|instrcallback|instrfind|instrfindall|int2str|integral(?:2|3)?|interp(?:1|1q|2|3|ft|n)|interpstreamspeed|intersect|intmax|intmin|inv|invhilb|ipermute|isa|isappdata|iscell|iscellstr|ischar|iscolumn|isdir|isempty|isequal|isequaln|isequalwithequalnans|isfield|isfinite|isfloat|isglobal|ishandle|ishghandle|ishold|isinf|isinteger|isjava|iskeyword|isletter|islogical|ismac|ismatrix|ismember|ismethod|isnan|isnumeric|isobject|isocaps|isocolors|isonormals|isosurface|ispc|ispref|isprime|isprop|isreal|isrow|isscalar|issorted|isspace|issparse|isstr|isstrprop|isstruct|isstudent|isunix|isvarname|isvector|javaaddpath|javaArray|javachk|javaclasspath|javacomponent|javaMethod|javaMethodEDT|javaObject|javaObjectEDT|javarmpath|jet|keyboard|kron|lasterr|lasterror|lastwarn|lcm|ldivide|ldl|le|legend|legendre|length|libfunctions|libfunctionsview|libisloaded|libpointer|libstruct|license|light|lightangle|lighting|lin2mu|line|lines|linkaxes|linkdata|linkprop|linsolve|linspace|listdlg|listfonts|load|loadlibrary|loadobj|log|log10|log1p|log2|loglog|logm|logspace|lookfor|lower|ls|lscov|lsqnonneg|lsqr|lt|lu|luinc|magic|makehgtform|mat2cell|mat2str|material|matfile|matlab\.io\.MatFile|matlab\.mixin\.(?:Copyable|Heterogeneous(?:\.getDefaultScalarElement)?)|matlabrc|matlabroot|max|maxNumCompThreads|mean|median|membrane|memmapfile|memory|menu|mesh|meshc|meshgrid|meshz|meta\.(?:class(?:\.fromName)?|DynamicProperty|EnumeratedValue|event|MetaData|method|package(?:\.(?:fromName|getAllPackages))?|property)|metaclass|methods|methodsview|mex(?:\.getCompilerConfigurations)?|MException|mexext|mfilename|min|minres|minus|mislocked|mkdir|mkpp|mldivide|mlint|mlintrpt|mlock|mmfileinfo|mmreader|mod|mode|more|move|movefile|movegui|movie|movie2avi|mpower|mrdivide|msgbox|mtimes|mu2lin|multibandread|multibandwrite|munlock|namelengthmax|nargchk|narginchk|nargoutchk|native2unicode|nccreate|ncdisp|nchoosek|ncinfo|ncread|ncreadatt|ncwrite|ncwriteatt|ncwriteschema|ndgrid|ndims|ne|NET(?:\.(?:addAssembly|Assembly|convertArray|createArray|createGeneric|disableAutoRelease|enableAutoRelease|GenericClass|invokeGenericMethod|NetException|setStaticProperty))?|netcdf\.(?:abort|close|copyAtt|create|defDim|defGrp|defVar|defVarChunking|defVarDeflate|defVarFill|defVarFletcher32|delAtt|endDef|getAtt|getChunkCache|getConstant|getConstantNames|getVar|inq|inqAtt|inqAttID|inqAttName|inqDim|inqDimID|inqDimIDs|inqFormat|inqGrpName|inqGrpNameFull|inqGrpParent|inqGrps|inqLibVers|inqNcid|inqUnlimDims|inqVar|inqVarChunking|inqVarDeflate|inqVarFill|inqVarFletcher32|inqVarID|inqVarIDs|open|putAtt|putVar|reDef|renameAtt|renameDim|renameVar|setChunkCache|setDefaultFormat|setFill|sync)|newplot|nextpow2|nnz|noanimate|nonzeros|norm|normest|not|notebook|now|nthroot|null|num2cell|num2hex|num2str|numel|nzmax|ode(?:113|15i|15s|23|23s|23t|23tb|45)|odeget|odeset|odextend|onCleanup|ones|open|openfig|opengl|openvar|optimget|optimset|or|ordeig|orderfields|ordqz|ordschur|orient|orth|pack|padecoef|pagesetupdlg|pan|pareto|parseSoapResponse|pascal|patch|path|path2rc|pathsep|pathtool|pause|pbaspect|pcg|pchip|pcode|pcolor|pdepe|pdeval|peaks|perl|perms|permute|pie|pink|pinv|planerot|playshow|plot|plot3|plotbrowser|plotedit|plotmatrix|plottools|plotyy|plus|pol2cart|polar|poly|polyarea|polyder|polyeig|polyfit|polyint|polyval|polyvalm|pow2|power|ppval|prefdir|preferences|primes|print|printdlg|printopt|printpreview|prod|profile|profsave|propedit|propertyeditor|psi|publish|PutCharArray|PutFullMatrix|PutWorkspaceData|pwd|qhull|qmr|qr|qrdelete|qrinsert|qrupdate|quad|quad2d|quadgk|quadl|quadv|questdlg|quit|quiver|quiver3|qz|rand|randi|randn|randperm|RandStream(?:\.(?:create|getDefaultStream|getGlobalStream|list|setDefaultStream|setGlobalStream))?|rank|rat|rats|rbbox|rcond|rdivide|readasync|real|reallog|realmax|realmin|realpow|realsqrt|record|rectangle|rectint|recycle|reducepatch|reducevolume|refresh|refreshdata|regexp|regexpi|regexprep|regexptranslate|rehash|rem|Remove|RemoveAll|repmat|reset|reshape|residue|restoredefaultpath|rethrow|rgb2hsv|rgb2ind|rgbplot|ribbon|rmappdata|rmdir|rmfield|rmpath|rmpref|rng|roots|rose|rosser|rot90|rotate|rotate3d|round|rref|rsf2csf|run|save|saveas|saveobj|savepath|scatter|scatter3|schur|sec|secd|sech|selectmoveresize|semilogx|semilogy|sendmail|serial|set|setappdata|setdiff|setenv|setfield|setpixelposition|setpref|setstr|setxor|shading|shg|shiftdim|showplottool|shrinkfaces|sign|sin(?:d|h)?|size|slice|smooth3|snapnow|sort|sortrows|sound|soundsc|spalloc|spaugment|spconvert|spdiags|specular|speye|spfun|sph2cart|sphere|spinmap|spline|spones|spparms|sprand|sprandn|sprandsym|sprank|spring|sprintf|spy|sqrt|sqrtm|squeeze|ss2tf|sscanf|stairs|startup|std|stem|stem3|stopasync|str2double|str2func|str2mat|str2num|strcat|strcmp|strcmpi|stream2|stream3|streamline|streamparticles|streamribbon|streamslice|streamtube|strfind|strjust|strmatch|strncmp|strncmpi|strread|strrep|strtok|strtrim|struct2cell|structfun|strvcat|sub2ind|subplot|subsasgn|subsindex|subspace|subsref|substruct|subvolume|sum|summer|superclasses|superiorto|support|surf|surf2patch|surface|surfc|surfl|surfnorm|svd|svds|swapbytes|symamd|symbfact|symmlq|symrcm|symvar|system|tan(?:d|h)?|tar|tempdir|tempname|tetramesh|texlabel|text|textread|textscan|textwrap|tfqmr|throw|tic|Tiff(?:\.(?:getTagNames|getVersion))?|timer|timerfind|timerfindall|times|timeseries|title|toc|todatenum|toeplitz|toolboxdir|trace|transpose|trapz|treelayout|treeplot|tril|trimesh|triplequad|triplot|TriRep|TriScatteredInterp|trisurf|triu|tscollection|tsearch|tsearchn|tstool|type|typecast|uibuttongroup|uicontextmenu|uicontrol|uigetdir|uigetfile|uigetpref|uiimport|uimenu|uiopen|uipanel|uipushtool|uiputfile|uiresume|uisave|uisetcolor|uisetfont|uisetpref|uistack|uitable|uitoggletool|uitoolbar|uiwait|uminus|undocheckout|unicode2native|union|unique|unix|unloadlibrary|unmesh|unmkpp|untar|unwrap|unzip|uplus|upper|urlread|urlwrite|usejava|userpath|validateattributes|validatestring|vander|var|vectorize|ver|verctrl|verLessThan|version|vertcat|VideoReader(?:\.isPlatformSupported)?|VideoWriter(?:\.getProfiles)?|view|viewmtx|visdiff|volumebounds|voronoi|voronoin|wait|waitbar|waitfor|waitforbuttonpress|warndlg|warning|waterfall|wavfinfo|wavplay|wavread|wavrecord|wavwrite|web|weekday|what|whatsnew|which|whitebg|who|whos|wilkinson|winopen|winqueryreg|winter|wk1finfo|wk1read|wk1write|workspace|xlabel|xlim|xlsfinfo|xlsread|xlswrite|xmlread|xmlwrite|xor|xslt|ylabel|ylim|zeros|zip|zlabel|zlim|zoom'
  ].join("|");
  var statsFunctions = [
    'addedvarplot|andrewsplot|anova(?:1|2|n)|ansaribradley|aoctool|barttest|bbdesign|beta(?:cdf|fit|inv|like|pdf|rnd|stat)|bino(?:cdf|fit|inv|pdf|rnd|stat)|biplot|bootci|bootstrp|boxplot|candexch|candgen|canoncorr|capability|capaplot|caseread|casewrite|categorical|ccdesign|cdfplot|chi2(?:cdf|gof|inv|pdf|rnd|stat)|cholcov|Classification(?:BaggedEnsemble|Discriminant(?:\.(?:fit|make|template))?|Ensemble|KNN(?:\.(?:fit|template))?|PartitionedEnsemble|PartitionedModel|Tree(?:\.(?:fit|template))?)|classify|classregtree|cluster|clusterdata|cmdscale|combnk|Compact(?:Classification(?:Discriminant|Ensemble|Tree)|Regression(?:Ensemble|Tree)|TreeBagger)|confusionmat|controlchart|controlrules|cophenet|copula(?:cdf|fit|param|pdf|rnd|stat)|cordexch|corr|corrcov|coxphfit|createns|crosstab|crossval|cvpartition|datasample|dataset|daugment|dcovary|dendrogram|dfittool|disttool|dummyvar|dwtest|ecdf|ecdfhist|ev(?:cdf|fit|inv|like|pdf|rnd|stat)|ExhaustiveSearcher|exp(?:cdf|fit|inv|like|pdf|rnd|stat)|factoran|fcdf|ff2n|finv|fitdist|fitensemble|fpdf|fracfact|fracfactgen|friedman|frnd|fstat|fsurfht|fullfact|gagerr|gam(?:cdf|fit|inv|like|pdf|rnd|stat)|GeneralizedLinearModel(?:\.fit)?|geo(?:cdf|inv|mean|pdf|rnd|stat)|gev(?:cdf|fit|inv|like|pdf|rnd|stat)|gline|glmfit|glmval|glyphplot|gmdistribution(?:\.fit)?|gname|gp(?:cdf|fit|inv|like|pdf|rnd|stat)|gplotmatrix|grp2idx|grpstats|gscatter|haltonset|harmmean|hist3|histfit|hmm(?:decode|estimate|generate|train|viterbi)|hougen|hyge(?:cdf|inv|pdf|rnd|stat)|icdf|inconsistent|interactionplot|invpred|iqr|iwishrnd|jackknife|jbtest|johnsrnd|KDTreeSearcher|kmeans|knnsearch|kruskalwallis|ksdensity|kstest|kstest2|kurtosis|lasso|lassoglm|lassoPlot|leverage|lhsdesign|lhsnorm|lillietest|LinearModel(?:\.fit)?|linhyptest|linkage|logn(?:cdf|fit|inv|like|pdf|rnd|stat)|lsline|mad|mahal|maineffectsplot|manova1|manovacluster|mdscale|mhsample|mle|mlecov|mnpdf|mnrfit|mnrnd|mnrval|moment|multcompare|multivarichart|mvn(?:cdf|pdf|rnd)|mvregress|mvregresslike|mvt(?:cdf|pdf|rnd)|NaiveBayes(?:\.fit)?|nan(?:cov|max|mean|median|min|std|sum|var)|nbin(?:cdf|fit|inv|pdf|rnd|stat)|ncf(?:cdf|inv|pdf|rnd|stat)|nct(?:cdf|inv|pdf|rnd|stat)|ncx2(?:cdf|inv|pdf|rnd|stat)|NeighborSearcher|nlinfit|nlintool|nlmefit|nlmefitsa|nlparci|nlpredci|nnmf|nominal|NonLinearModel(?:\.fit)?|norm(?:cdf|fit|inv|like|pdf|rnd|stat)|normplot|normspec|ordinal|outlierMeasure|parallelcoords|paretotails|partialcorr|pcacov|pcares|pdf|pdist|pdist2|pearsrnd|perfcurve|perms|piecewisedistribution|plsregress|poiss(?:cdf|fit|inv|pdf|rnd|tat)|polyconf|polytool|prctile|princomp|ProbDist(?:Kernel|Parametric|UnivKernel|UnivParam)?|probplot|procrustes|qqplot|qrandset|qrandstream|quantile|randg|random|randsample|randtool|range|rangesearch|ranksum|rayl(?:cdf|fit|inv|pdf|rnd|stat)|rcoplot|refcurve|refline|regress|Regression(?:BaggedEnsemble|Ensemble|PartitionedEnsemble|PartitionedModel|Tree(?:\.(?:fit|template))?)|regstats|relieff|ridge|robustdemo|robustfit|rotatefactors|rowexch|rsmdemo|rstool|runstest|sampsizepwr|scatterhist|sequentialfs|signrank|signtest|silhouette|skewness|slicesample|sobolset|squareform|statget|statset|stepwise|stepwisefit|surfht|tabulate|tblread|tblwrite|tcdf|tdfread|tiedrank|tinv|tpdf|TreeBagger|treedisp|treefit|treeprune|treetest|treeval|trimmean|trnd|tstat|ttest|ttest2|unid(?:cdf|inv|pdf|rnd|stat)|unif(?:cdf|inv|it|pdf|rnd|stat)|vartest(?:2|n)?|wbl(?:cdf|fit|inv|like|pdf|rnd|stat)|wblplot|wishrnd|x2fx|xptread|zscore|ztest'
  ].join("|");
  var imageFunctions = [
    'adapthisteq|analyze75info|analyze75read|applycform|applylut|axes2pix|bestblk|blockproc|bwarea|bwareaopen|bwboundaries|bwconncomp|bwconvhull|bwdist|bwdistgeodesic|bweuler|bwhitmiss|bwlabel|bwlabeln|bwmorph|bwpack|bwperim|bwselect|bwtraceboundary|bwulterode|bwunpack|checkerboard|col2im|colfilt|conndef|convmtx2|corner|cornermetric|corr2|cp2tform|cpcorr|cpselect|cpstruct2pairs|dct2|dctmtx|deconvblind|deconvlucy|deconvreg|deconvwnr|decorrstretch|demosaic|dicom(?:anon|dict|info|lookup|read|uid|write)|edge|edgetaper|entropy|entropyfilt|fan2para|fanbeam|findbounds|fliptform|freqz2|fsamp2|fspecial|ftrans2|fwind1|fwind2|getheight|getimage|getimagemodel|getline|getneighbors|getnhood|getpts|getrangefromclass|getrect|getsequence|gray2ind|graycomatrix|graycoprops|graydist|grayslice|graythresh|hdrread|hdrwrite|histeq|hough|houghlines|houghpeaks|iccfind|iccread|iccroot|iccwrite|idct2|ifanbeam|im2bw|im2col|im2double|im2int16|im2java2d|im2single|im2uint16|im2uint8|imabsdiff|imadd|imadjust|ImageAdapter|imageinfo|imagemodel|imapplymatrix|imattributes|imbothat|imclearborder|imclose|imcolormaptool|imcomplement|imcontour|imcontrast|imcrop|imdilate|imdisplayrange|imdistline|imdivide|imellipse|imerode|imextendedmax|imextendedmin|imfill|imfilter|imfindcircles|imfreehand|imfuse|imgca|imgcf|imgetfile|imhandles|imhist|imhmax|imhmin|imimposemin|imlincomb|imline|immagbox|immovie|immultiply|imnoise|imopen|imoverview|imoverviewpanel|impixel|impixelinfo|impixelinfoval|impixelregion|impixelregionpanel|implay|impoint|impoly|impositionrect|improfile|imputfile|impyramid|imreconstruct|imrect|imregconfig|imregionalmax|imregionalmin|imregister|imresize|imroi|imrotate|imsave|imscrollpanel|imshow|imshowpair|imsubtract|imtool|imtophat|imtransform|imview|ind2gray|ind2rgb|interfileinfo|interfileread|intlut|ippl|iptaddcallback|iptcheckconn|iptcheckhandle|iptcheckinput|iptcheckmap|iptchecknargin|iptcheckstrs|iptdemos|iptgetapi|iptGetPointerBehavior|iptgetpref|ipticondir|iptnum2ordinal|iptPointerManager|iptprefs|iptremovecallback|iptSetPointerBehavior|iptsetpref|iptwindowalign|iradon|isbw|isflat|isgray|isicc|isind|isnitf|isrgb|isrset|lab2double|lab2uint16|lab2uint8|label2rgb|labelmatrix|makecform|makeConstrainToRectFcn|makehdr|makelut|makeresampler|maketform|mat2gray|mean2|medfilt2|montage|nitfinfo|nitfread|nlfilter|normxcorr2|ntsc2rgb|openrset|ordfilt2|otf2psf|padarray|para2fan|phantom|poly2mask|psf2otf|qtdecomp|qtgetblk|qtsetblk|radon|rangefilt|reflect|regionprops|registration\.metric\.(?:MattesMutualInformation|MeanSquares)|registration\.optimizer\.(?:OnePlusOneEvolutionary|RegularStepGradientDescent)|rgb2gray|rgb2ntsc|rgb2ycbcr|roicolor|roifill|roifilt2|roipoly|rsetwrite|std2|stdfilt|strel|stretchlim|subimage|tformarray|tformfwd|tforminv|tonemap|translate|truesize|uintlut|viscircles|warp|watershed|whitepoint|wiener2|xyz2double|xyz2uint16|ycbcr2rgb'
  ].join("|");
  var optimFunctions = [
    'bintprog|color|fgoalattain|fminbnd|fmincon|fminimax|fminsearch|fminunc|fseminf|fsolve|fzero|fzmult|gangstr|ktrlink|linprog|lsqcurvefit|lsqlin|lsqnonlin|lsqnonneg|optimget|optimset|optimtool|quadprog'
  ].join("|");

  // identifiers: variable/function name, or a chain of variable names joined by dots (obj.method, struct.field1.field2, etc..)
  // valid variable names (start with letter, and contains letters, digits, and underscores).
  // we match "xx.yy" as a whole so that if "xx" is plain and "yy" is not, we dont get a false positive for "yy"
  //var reIdent = '(?:[a-zA-Z][a-zA-Z0-9_]*)';
  //var reIdentChain = '(?:' + reIdent + '(?:\.' + reIdent + ')*' + ')';

  // patterns that always start with a known character. Must have a shortcut string.
  var shortcutStylePatterns = [
    // whitespaces: space, tab, carriage return, line feed, line tab, form-feed, non-break space
    [PR.PR_PLAIN, /^[ \t\r\n\v\f\xA0]+/, null, " \t\r\n\u000b\u000c\u00a0"],

    // block comments
    //TODO: chokes on nested block comments
    //TODO: false positives when the lines with %{ and %} contain non-spaces
    //[PR.PR_COMMENT, /^%(?:[^\{].*|\{(?:%|%*[^\}%])*(?:\}+%?)?)/, null],
    [PR.PR_COMMENT, /^%\{[^%]*%+(?:[^\}%][^%]*%+)*\}/, null],

    // single-line comments
    [PR.PR_COMMENT, /^%[^\r\n]*/, null, "%"],

    // system commands
    [PR_SYSCMD, /^![^\r\n]*/, null, "!"]
  ];

  // patterns that will be tried in order if the shortcut ones fail. May have shortcuts.
  var fallthroughStylePatterns = [
    // line continuation
    [PR_LINE_CONTINUATION, /^\.\.\.\s*[\r\n]/, null],

    // error message
    [PR_ERROR, /^\?\?\? [^\r\n]*/, null],

    // warning message
    [PR_WARNING, /^Warning: [^\r\n]*/, null],

    // command prompt/output
    //[PR_CODE_OUTPUT, /^>>\s+[^\r\n]*[\r\n]{1,2}[^=]*=[^\r\n]*[\r\n]{1,2}[^\r\n]*/, null],    // full command output (both loose/compact format): `>> EXP\nVAR =\n VAL`
    [PR_CODE_OUTPUT, /^>>\s+/, null],      // only the command prompt `>> `
    [PR_CODE_OUTPUT, /^octave:\d+>\s+/, null],  // Octave command prompt `octave:1> `

    // identifier (chain) or closing-parenthesis/brace/bracket, and IS followed by transpose operator
    // this way we dont misdetect the transpose operator ' as the start of a string
    ["lang-matlab-operators", /^((?:[a-zA-Z][a-zA-Z0-9_]*(?:\.[a-zA-Z][a-zA-Z0-9_]*)*|\)|\]|\}|\.)')/, null],

    // single-quoted strings: allow for escaping with '', no multilines
    //[PR.PR_STRING, /(?:(?<=(?:\(|\[|\{|\s|=|;|,|:))|^)'(?:[^']|'')*'(?=(?:\)|\]|\}|\s|=|;|,|:|~|<|>|&|-|\+|\*|\.|\^|\|))/, null],  // string vs. transpose (check before/after context using negative/positive lookbehind/lookahead)
    [PR.PR_STRING, /^'(?:[^']|'')*'/, null],  // "'"

    // floating point numbers: 1, 1.0, 1i, -1.1E-1
    [PR.PR_LITERAL, /^[+\-]?\.?\d+(?:\.\d*)?(?:[Ee][+\-]?\d+)?[ij]?/, null],

    // parentheses, braces, brackets
    [PR.PR_TAG, /^(?:\{|\}|\(|\)|\[|\])/, null],  // "{}()[]"

    // other operators
    [PR.PR_PUNCTUATION, /^(?:<|>|=|~|@|&|;|,|:|!|\-|\+|\*|\^|\.|\||\\|\/)/, null]
  ];

  var identifiersPatterns = [
    // list of keywords (`iskeyword`)
    [PR.PR_KEYWORD, /^\b(?:break|case|catch|classdef|continue|else|elseif|end|for|function|global|if|otherwise|parfor|persistent|return|spmd|switch|try|while)\b/, null],

    // some specials variables/constants
    [PR_CONSTANT, /^\b(?:true|false|inf|Inf|nan|NaN|eps|pi|ans|nargin|nargout|varargin|varargout)\b/, null],

    // some data types
    [PR.PR_TYPE, /^\b(?:cell|struct|char|double|single|logical|u?int(?:8|16|32|64)|sparse)\b/, null],

    // commonly used builtin functions from core MATLAB and a few popular toolboxes
    [PR_FUNCTION, new RegExp('^\\b(?:' + coreFunctions + ')\\b'), null],
    [PR_FUNCTION_TOOLBOX, new RegExp('^\\b(?:' + statsFunctions + ')\\b'), null],
    [PR_FUNCTION_TOOLBOX, new RegExp('^\\b(?:' + imageFunctions + ')\\b'), null],
    [PR_FUNCTION_TOOLBOX, new RegExp('^\\b(?:' + optimFunctions + ')\\b'), null],

    // plain identifier (user-defined variable/function name)
    [PR_IDENTIFIER, /^[a-zA-Z][a-zA-Z0-9_]*(?:\.[a-zA-Z][a-zA-Z0-9_]*)*/, null]
  ];

  var operatorsPatterns = [
    // forward to identifiers to match
    ["lang-matlab-identifiers", /^([a-zA-Z][a-zA-Z0-9_]*(?:\.[a-zA-Z][a-zA-Z0-9_]*)*)/, null],

    // parentheses, braces, brackets
    [PR.PR_TAG, /^(?:\{|\}|\(|\)|\[|\])/, null],  // "{}()[]"

    // other operators
    [PR.PR_PUNCTUATION, /^(?:<|>|=|~|@|&|;|,|:|!|\-|\+|\*|\^|\.|\||\\|\/)/, null],

    // transpose operators
    [PR_TRANSPOSE, /^'/, null]
  ];

  PR.registerLangHandler(
    PR.createSimpleLexer([], identifiersPatterns),
    ["matlab-identifiers"]
  );
  PR.registerLangHandler(
    PR.createSimpleLexer([], operatorsPatterns),
    ["matlab-operators"]
  );
  PR.registerLangHandler(
    PR.createSimpleLexer(shortcutStylePatterns, fallthroughStylePatterns),
    ["matlab"]
  );
})(window['PR']);
DELIMITER";
extensions["m"] = matlab;
extensions["matlab"] = matlab;
string lua = q"DELIMITER
PR.registerLangHandler(PR.createSimpleLexer([[PR.PR_PLAIN,/^[\t\n\r \xA0]+/,null,"  \n\r  "],[PR.PR_STRING,/^(?:\"(?:[^\"\\]|\\[\s\S])*(?:\"|$)|\'(?:[^\'\\]|\\[\s\S])*(?:\'|$))/,null,"\"'"]],[[PR.PR_COMMENT,/^--(?:\[(=*)\[[\s\S]*?(?:\]\1\]|$)|[^\r\n]*)/],[PR.PR_STRING,/^\[(=*)\[[\s\S]*?(?:\]\1\]|$)/],[PR.PR_KEYWORD,/^(?:and|break|do|else|elseif|end|false|for|function|if|in|local|nil|not|or|repeat|return|then|true|until|while)\b/,null],[PR.PR_LITERAL,/^[+-]?(?:0x[\da-f]+|(?:(?:\.\d+|\d+(?:\.\d*)?)(?:e[+\-]?\d+)?))/i],[PR.PR_PLAIN,/^[a-z_]\w*/i],[PR.PR_PUNCTUATION,/^[^\w\t\n\r \xA0][^\w\t\n\r \xA0\"\'\-\+=]*/]]),["lua"]);
DELIMITER";
extensions["lua"] = lua;
string ocaml = q"DELIMITER
PR.registerLangHandler(PR.createSimpleLexer([[PR.PR_PLAIN,/^[\t\n\r \xA0]+/,null,"  \n\r  "],[PR.PR_COMMENT,/^#(?:if[\t\n\r \xA0]+(?:[a-z_$][\w\']*|``[^\r\n\t`]*(?:``|$))|else|endif|light)/i,null,"#"],[PR.PR_STRING,/^(?:\"(?:[^\"\\]|\\[\s\S])*(?:\"|$)|\'(?:[^\'\\]|\\[\s\S])(?:\'|$))/,null,"\"'"]],[[PR.PR_COMMENT,/^(?:\/\/[^\r\n]*|\(\*[\s\S]*?\*\))/],[PR.PR_KEYWORD,/^(?:abstract|and|as|assert|begin|class|default|delegate|do|done|downcast|downto|elif|else|end|exception|extern|false|finally|for|fun|function|if|in|inherit|inline|interface|internal|lazy|let|match|member|module|mutable|namespace|new|null|of|open|or|override|private|public|rec|return|static|struct|then|to|true|try|type|upcast|use|val|void|when|while|with|yield|asr|land|lor|lsl|lsr|lxor|mod|sig|atomic|break|checked|component|const|constraint|constructor|continue|eager|event|external|fixed|functor|global|include|method|mixin|object|parallel|process|protected|pure|sealed|trait|virtual|volatile)\b/],[PR.PR_LITERAL,/^[+\-]?(?:0x[\da-f]+|(?:(?:\.\d+|\d+(?:\.\d*)?)(?:e[+\-]?\d+)?))/i],[PR.PR_PLAIN,/^(?:[a-z_][\w']*[!?#]?|``[^\r\n\t`]*(?:``|$))/i],[PR.PR_PUNCTUATION,/^[^\t\n\r \xA0\"\'\w]+/]]),["fs","ml"]);
DELIMITER";
extensions["fs"] = ocaml;
extensions["ml"] = ocaml;

// css
string colorschemeCSS = q"DELIMITER
.pln{color:#1b181b}
.str{color:#918b3b}
.kwd{color:#7b59c0}
.com{color:#9e8f9e}
.typ{color:#516aec}
.lit{color:#a65926}
.clo,
.opn,
.pun{color:#1b181b}
.tag{color:#ca402b}
.atn{color:#a65926}
.atv{color:#159393}
.dec{color:#a65926}
.var{color:#ca402b}
.fun{color:#516aec}
pre.prettyprint
{
	background:#f7f3f7;
	color:#ab9bab;
	font-family:Menlo,Consolas,"Bitstream Vera Sans Mono","DejaVu Sans Mono",Monaco,monospace;
	font-size:12px;
	line-height:1.5;
	border:1px solid #d8cad8;
	padding:10px
}
ol.linenums{margin-top:0;margin-bottom:0}
DELIMITER";

string defaultCSS = q"DELIMITER
html {
 	font-family:"Avenir", "Helvetica neue", sans-serif;
}

body {
  background: #ffffff;
  color: #555;
}

#title {
	font-size: 40px;
}

h1, body, title {
    color: rgb(100, 100, 100);
    font-weight: normal;
}

h2 {
  font-weight: normal;
}

h3 {
  font-weight: normal;
}

h4 {
  font-weight: normal;
}

h5 {
  font-weight: normal;
}

h6 {
  font-weight: normal;
}

p, li, dd, dt, th, td {
	font-size: 12px;
}

p {
	padding-bottom: 10px;
}

pre {
	padding-top: 0px;
	margin-top: 0px;
}

p:not(.notp){
	text-indent: 0em;
}

a:link {
    color: rgb(22, 123, 204);
}

/* visited link */
a:visited {
    color: rgb(22, 123, 204);
}

/* mouse over link */
a:hover {
    color: rgb(22, 123, 204);
}

/* selected link */
a:active {
    color: rgb(22, 123, 204);
}

th, td {
    padding-right: 10px;
    padding-bottom: 5px;
    vertical-align: top;
}

DELIMITER";


    string output;

// Write the head of the HTML
string prettifyExtension;
foreach (cmd; p.commands) 
{
    if (cmd.name == "@overwrite_css") 
    {
        defaultCSS = readall(File(cmd.args));
    } 
    else if (cmd.name == "@add_css") 
    {
        defaultCSS ~= readall(File(cmd.args));
    } 
    else if (cmd.name == "@colorscheme") 
    {
        colorschemeCSS = readall(File(cmd.args));
    }

    if (cmd.name == "@code_type") 
    {
        if (cmd.args.length > 1) 
        {
            string ext = cmd.args.split()[1][1..$];
            if (ext in extensions) 
            {
                prettifyExtension = "<script>\n" ~ extensions[ext] ~ "</script>\n";
            }
        }
    }
}
foreach (cmd; c.commands) 
{
    if (cmd.name == "@overwrite_css") 
    {
        defaultCSS = readall(File(cmd.args));
    } 
    else if (cmd.name == "@add_css") 
    {
        defaultCSS ~= readall(File(cmd.args));
    } 
    else if (cmd.name == "@colorscheme") 
    {
        colorschemeCSS = readall(File(cmd.args));
    }

    if (cmd.name == "@code_type") 
    {
        if (cmd.args.length > 1) 
        {
            string ext = cmd.args.split()[1][1..$];
            if (ext in extensions) 
            {
                prettifyExtension = "<script>\n" ~ extensions[ext] ~ "</script>\n";
            }
        }
    }
}

string css = colorschemeCSS ~ defaultCSS;
string bootstrapcss = q"DELIMITER
<!-- Bootstrap CSS -->
<link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.1.3/css/bootstrap.min.css" integrity="sha384-MCw98/SFnGE8fJT3GXwEOngsV7Zt27NXFoaoApmYm81iuXoPkFOJwJ8ERdknLPMO" crossorigin="anonymous">
 <link rel="stylesheet" href="https://cdn.rawgit.com/afeld/bootstrap-toc/v1.0.0/dist/bootstrap-toc.min.css">
DELIMITER";
string scripts = "<script>\n" ~ prettify ~ "</script>\n";
scripts ~= prettifyExtension;

string bootstrapscript = q"DELIMITER
<script src="https://code.jquery.com/jquery-3.3.1.slim.min.js" integrity="sha384-q8i/X+965DzO0rT7abK41JStQIAqVgRVzpbzo5smXKp4YfRvH+8abtTE1Pi6jizo" crossorigin="anonymous"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/popper.js/1.14.3/umd/popper.min.js" integrity="sha384-ZMP7rVo3mIykV+2+9J3UJ46jBk0WLaUAdn689aCwoqbBJiSnjAK/l8WvCWPIPm49" crossorigin="anonymous"></script>
<script src="https://stackpath.bootstrapcdn.com/bootstrap/4.1.3/js/bootstrap.min.js" integrity="sha384-ChfqqxuZUCnJSK3+MXmPNIyE6ZbWh2IMqE241rYiqJxyMiZ6OW/JmZQ5stwEULTy" crossorigin="anonymous"></script>
<script src="https://cdn.rawgit.com/afeld/bootstrap-toc/v1.0.0/dist/bootstrap-toc.min.js"></script>
DELIMITER";

scripts ~= bootstrapscript;

bool use_katex = false;

output ~= "<!DOCTYPE html>\n" ~
             "<html>\n" ~
             "<head>\n" ~
             "<meta charset=\"utf-8\">\n" ~
             "<title>" ~ c.title ~ "</title>\n" ~
             bootstrapcss ~
             scripts ~
             "<style>\n" ~
             css ~
             "</style>\n" ~
             "</head>\n";

// Write the body
output ~= q"DELIMITER
<body onload="prettyPrint()"  data-spy="scroll" data-target="#toc">
<div class="row">
<div class="col-sm-3">
<nav id="toc" data-spy="affix" data-toggle="toc"></nav>
</div>
<div class="col-sm-9">
DELIMITER";
output ~= "<p id=\"title\">" ~ c.title ~ "</p>";

foreach (s; c.sections) 
{
	string noheading = s.title == "" ? " class=\"noheading\"" : "";
    output ~= "<a name=\"" ~ c.num() ~ ":" ~ s.numToString() ~ "\"><div class=\"section\"><h" ~ to!string(s.level + 1) ~
              noheading ~ ">" ~ s.numToString() ~ ". " ~ s.title ~ "</h" ~ to!string(s.level + 1) ~ "></a>\n";
    
    foreach (block; s.blocks) 
    {
        if (!block.modifiers.canFind(Modifier.noWeave)) 
        {
            if (!block.isCodeblock) 
            {
                // Weave a prose block
                string html;
                string md;
                
                foreach (lineObj; block.lines) 
                {
                    auto l = lineObj.text;
                    if (l.matchAll(regex(r"@\{.*?\}"))) 
                    {
                        auto matches = l.matchAll(regex(r"@\{(.*?)\}"));
                        foreach (m; matches) 
                        {
                            auto def = "";
                            auto defLocation = "";
                            auto str = strip(m[1]);
                            if (str !in defLocations) 
                            {
                                error(lineObj.file, lineObj.lineNum, "{" ~ str ~ "} is never defined");
                            } 
                            else if (defLocations[str] != "noWeave") 
                            {
                                def = defLocations[str];
                                defLocation = def;
                                auto index = def.indexOf(":");
                                string chapter = def[0..index];
                                auto htmlFile = getChapterHtmlFile(p.chapters, chapter);
                                if (chapter == c.num()) defLocation = def[index + 1..$];       
                                l = l.replaceAll(regex(r"@\{" ~ str ~ r"\}"), "`{" ~ str ~ ",`[`" ~ defLocation ~ "`](" ~ htmlFile ~ "#" ~ def ~ ")`}`");
                            }
                        }
                    }
                    md ~= l ~ "\n";
                }
                
                if (md.matchAll(regex(r"(?<!\\)[\$](?<!\\)[\$](.*?)(?<!\\)[\$](?<!\\)[\$]")) || md.matchAll(regex(r"(?<!\\)[\$](.*?)(?<!\\)[\$]"))) 
                {
                    use_katex = true;
                }
                
                md = md.replaceAll(regex(r"(?<!\\)[\$](?<!\\)[\$](.*?)(?<!\\)[\$](?<!\\)[\$]", "s"), "<div class=\"math\">$1</div>");
                md = md.replaceAll(regex(r"(?<!\\)[\$](.*?)(?<!\\)[\$]", "s"), "<span class=\"math\">$1</span>");
                md = md.replaceAll(regex(r"\\\$"), "$$");
                
                
                if (useMdCompiler) 
                {
                    auto pipes = pipeShell(mdCompilerCmd, Redirect.stdin | Redirect.stdout | Redirect.stderrToStdout);
                    pipes.stdin.write(md);
                    pipes.stdin.flush();
                    pipes.stdin.close();
                    auto status = wait(pipes.pid);
                    string mdCompilerOutput;
                    foreach (line; pipes.stdout.byLine) mdCompilerOutput ~= line.idup;
                    if (status != 0) 
                    {
                        warn(c.file, 1, "Custom markdown compilation failed: " ~ mdCompilerOutput ~ " -- Falling back to built-in markdown compiler");
                        html = filterMarkdown(md, MarkdownFlags.disableUnderscoreEmphasis);
                        useMdCompiler = false;
                    } 
                    else 
                    {
                        html = mdCompilerOutput;
                    }
                } 
                else 
                {
                    html = filterMarkdown(md, MarkdownFlags.disableUnderscoreEmphasis);
                }
                
                output ~= html ~ "\n";

            } 
            else 
            {
                // Weave a code block
                output ~= "<div class=\"codeblock\">\n";
                
                // Write the title out
                // Find the definition location
                string chapterNum;
                string def;
                string defLocation;
                string htmlFile = "";
                if (block.name !in defLocations) 
                {
                    error(block.startLine.file, block.startLine.lineNum, "{" ~ block.name ~ "} is never defined");
                } 
                else 
                {
                    def = defLocations[block.name];
                    defLocation = def;
                    auto index = def.indexOf(":");
                    string chapter = def[0..index];
                    htmlFile = getChapterHtmlFile(p.chapters, chapter);
                    if (chapter == c.num()) 
                    {
                        defLocation = def[index + 1..$];
                    }
                }
                string extra = "";
                if (block.modifiers.canFind(Modifier.additive)) 
                {
                    extra = " +=";
                } 
                else if (block.modifiers.canFind(Modifier.redef)) 
                {
                    extra = " :=";
                }

                // Make the title bold if necessary
                string name;
                if (block.isRootBlock) name = "<strong>" ~ block.name ~ "</strong>";
                else name = block.name;
                

                
                output ~= "<span class=\"codeblock_name\">{" ~ name ~
                          " <a href=\"" ~ htmlFile ~ "#" ~ def ~ "\">" ~ defLocation ~ "</a>}" ~ extra ~ "</span>\n";

                // Write the actual code
                if (block.codeType.split().length > 1) 
                {
                    if (block.codeType.split()[1].indexOf(".") == -1) 
                    {
                        warn(block.startLine.file, 1, "@code_type extension must begin with a '.', for example: `@code_type c .c`");
                    } 
                    else 
                    {
                        output ~= "<pre class=\"prettyprint lang-" ~ block.codeType.split()[1][1..$] ~ "\">\n";
                    }
                } 
                else 
                {
                    output ~= "<pre class=\"prettyprint\">\n";
                }
                
                foreach (lineObj; block.lines) 
                {
                    // Write the line
                    string line = lineObj.text;
                    string strippedLine = strip(line);
                    if (strippedLine.startsWith("@{") && strippedLine.endsWith("}")) 
                    {
                        // Link a used codeblock
                        def = "";
                        defLocation = "";
                        if (strip(strippedLine[2..$ - 1]) !in defLocations) 
                        {
                            error(lineObj.file, lineObj.lineNum, "{" ~ strip(strippedLine[2..$ - 1]) ~ "} is never defined");
                        } 
                        else if (defLocations[strip(strippedLine[2..$ - 1])] != "noWeave") 
                        {
                            def = defLocations[strippedLine[2..$ - 1]];
                            defLocation = def;
                            auto index = def.indexOf(":");
                            string chapter = def[0..index];
                            htmlFile = getChapterHtmlFile(p.chapters, chapter);
                            if (chapter == c.num()) 
                            {
                                defLocation = def[index + 1..$];
                            }
                            def = ", <a href=\"" ~ htmlFile ~ "#" ~ def ~ "\">" ~ defLocation ~ "</a>";
                        }
                        output ~= "<span class=\"nocode pln\">" ~ leadingWS(line) ~ "{" ~ strippedLine[2..$ - 1] ~ def ~ "}</span>\n";

                    } 
                    else 
                    {
                        output ~= line.replace("&", "&amp;").replace(">", "&gt;").replace("<", "&lt;") ~ "\n";
                    }

                }
                output ~= "</pre>\n";

                // Write the 'added to' links
                output ~= linkLocations("Added to in section", addLocations, p, c, s, block) ~ "\n";

                // Write the 'redefined in' links
                output ~= linkLocations("Redefined in section", redefLocations, p, c, s, block) ~ "\n";

                // Write the 'used in' links
                output ~= linkLocations("Used in section", useLocations, p, c, s, block) ~ "\n";

                
                output ~= "</div>\n";

            }
        }
    }
	output ~= "</div>\n";
}

output ~= "</div>\n"; // matches <div class="col-sm-9">
output ~= "</div>\n"; // matches <div class="row">


	if (use_katex) 
	{
// Write the katex source
output ~= "<link rel=\"stylesheet\" href=\"http://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.3.0/katex.min.css\">\n" ~
"<script src=\"http://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.3.0/katex.min.js\"></script>\n";
output ~= q"DELIMITER
<script>
var mathDivs = document.getElementsByClassName("math")
for (var i = 0; i < mathDivs.length; i++) {
    var el = mathDivs[i];
    var texTxt = el.textContent;
    try {
        var displayMode = false;
        if (el.tagName == 'DIV') {
            displayMode = true;
        }
        katex.render(texTxt, el, {displayMode: displayMode});
    }
    catch(err) {
        el.innerHTML = "<span class='err'>"+err+"</span>";
    }
}
</script>
DELIMITER";

    }

    if (isBook) {
        output ~= "<br>";
        int index = cast(int) p.chapters.countUntil(c);
        if (index - 1 >= 0) 
        {
            Chapter lastChapter = p.chapters[p.chapters.countUntil(c)-1];
            output ~= "<a style=\"float:left;\" class=\"chapter-nav\" href=\"" ~ stripExtension(baseName(lastChapter.file)) ~ ".html\">Previous Chapter</a>";
        }
        if (index + 1 < p.chapters.length) 
        {
            Chapter nextChapter = p.chapters[p.chapters.countUntil(c)+1];
            output ~= "<a style=\"float:right;\" class=\"chapter-nav\" href=\"" ~ stripExtension(baseName(nextChapter.file)) ~ ".html\">Next Chapter</a>";
        }
    }

    output ~= "</body>\n";
    return output;
}

// LinkLocations function
T[] noDupes(T)(in T[] s) 
{
    import std.algorithm: canFind;
    T[] result;
    foreach (T c; s)
    {
        if (!result.canFind(c)) result ~= c;
    }
    return result;
}

string linkLocations(string text, string[][string] sectionLocations, Program p, Chapter c, Section s, parser.Block block) 
{
    if (block.name in sectionLocations) 
    {
        string[] locations = dup(sectionLocations[block.name]).noDupes;

        if (locations.canFind(c.num() ~ ":" ~ s.numToString())) 
        {
            locations = remove(locations, locations.countUntil(c.num() ~ ":" ~ s.numToString()));
        }

        if (locations.length > 0) 
        {
            string seealso = "<p class=\"seealso\">" ~ text;

            if (locations.length > 1) seealso ~= "s ";
            else seealso ~= " ";
            
            foreach (i; 0 .. locations.length) 
            {
                string loc = locations[i];
                string locName = loc;
                auto index = loc.indexOf(":");
                string chapter = loc[0..index];
                string htmlFile = getChapterHtmlFile(p.chapters, chapter);
                if (chapter == c.num()) locName = loc[index + 1..$];
                loc = "<a href=\"" ~ htmlFile ~ "#" ~ loc ~ "\">" ~ locName ~ "</a>";
                if (i == 0) seealso ~= loc;
                else if (i == locations.length - 1) seealso ~= " and " ~ loc;
                else seealso ~= ", " ~ loc;
                
            }
            seealso ~= "</p>";
            return seealso;
        }
    }
    return "";
}



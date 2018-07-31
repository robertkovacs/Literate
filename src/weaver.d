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
	font-size: 14px;
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

    string prettify;
    string[string] extensions;

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
                
                output ~= md ~ "\n";

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



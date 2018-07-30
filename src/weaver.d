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
            File f = File(dir ~ "/" ~ stripExtension(baseName(c.file)) ~ "- woven.md", "w");
            f.write(output);
            f.close();
        }
    }

    if (isBook && !noOutput) 
    {
		// Create the table of contents
		string dir = outDir ~ "/_book";
		File f = File(dir ~ "/" ~ p.title ~ "_contents.md", "w");
		
		f.writeln("# " ~ p.title);
		f.writeln(p.text);
		
		foreach (c; p.chapters) 
		{
		    f.writeln(c.num() ~ "[" ~ stripExtension(baseName(c.file)) ~ "]" ~ c.title);
		}
		
		f.close();

    }
}

// WeaveChapter
string weaveChapter(Chapter c, Program p, string[string] defLocations,
                    string[][string] redefLocations, string[][string] addLocations,
                    string[][string] useLocations) 
{
    string output = "";
    // Write the body
    foreach (s; c.sections) 
    {
        output ~= c.num() ~ ":" ~ s.numToString() ~ s.numToString() ~ ". " ~ s.title ~ "\n";
    
        foreach (block; s.blocks) 
        {
            if (!block.modifiers.canFind(Modifier.noWeave)) 
            {
                if (!block.isCodeblock) 
                {
                    // Weave a prose block
                    string md = "";
                    
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
                                    auto mdFile = getChapterMdFile(p.chapters, chapter);
                                    if (chapter == c.num()) defLocation = def[index + 1..$];       
                                    l = l.replaceAll(regex(r"@\{" ~ str ~ r"\}"), "`{" ~ str ~ ",`[`" ~ defLocation ~ "`](" ~ mdFile ~ "#" ~ def ~ ")`}`");
                                }
                            }
                        }
                        md ~= l ~ "\n";
                    }
                    
                    output ~= md ~ "\n";

                } 
                else 
                {
                    // Weave a code block
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


                }
            }
        }
    
    }

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



// src/globals.d
// Globals
bool tangleOnly;
bool isBook;
bool weaveOnly;
bool noOutput;
bool noCompCmd = true;
bool tangleErrors;
bool useStdin;
bool lineDirectives;
bool useMdCompiler;
string mdCompilerCmd;
string versionNum = "0.1";
string outDir = "."; // Default is current directory
string lineDirectiveStr;

string helpText = q"DELIMITER
Lit: Literate Programming System

Usage: lit [options] <inputs>

Options:
--help       -h         Show this help text
--tangle     -t         Only compile code files
--weave      -w         Only compile HTML files
--no-output  -no        Do not generate any output files
--out-dir    -odir DIR  Put the generated files in DIR
--compiler   -c         Report compiler errors (needs @compiler to be defined)
--linenums   -l    STR  Write line numbers prepended with STR to the output file
--md-compiler COMPILER  Use COMPILER as the markdown compiler instead of the built-in one
--version    -v         Show the version number and compiler information
DELIMITER";

// Modifiers
enum Modifier 
{
    noWeave,
    noTangle, // Not yet implemented
    noComment,
    additive, // +=
    redef // :=
}



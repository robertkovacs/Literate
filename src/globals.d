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

string helpText =
"Lit: Literate Programming System\n"
"\n"
"Usage: lit [options] <inputs>\n"
"\n"
"Options:\n"
"--help       -h         Show this help text\n"
"--tangle     -t         Only compile code files\n"
"--weave      -w         Only compile HTML files\n"
"--no-output  -no        Do not generate any output files\n"
"--out-dir    -odir DIR  Put the generated files in DIR\n"
"--compiler   -c         Report compiler errors (needs @compiler to be defined)\n"
"--linenums   -l    STR  Write line numbers prepended with STR to the output file\n"
"--md-compiler COMPILER  Use COMPILER as the markdown compiler instead of the built-in one\n"
"--version    -v         Show the version number and compiler information";

// Modifiers
enum Modifier 
{
    noWeave,
    noTangle, // Not yet implemented
    noComment,
    additive, // +=
    redef // :=
}



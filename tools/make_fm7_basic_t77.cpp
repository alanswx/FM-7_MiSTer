// Small build-time helper for the magazine examples.
// Uses the repository's 77AVEMU T77 encoder to wrap an ASCII F-BASIC listing.

#include <fstream>
#include <iostream>
#include <iterator>
#include <vector>

#include "t77.h"
#include "cpplib.h"

int main(int argc, char **argv)
{

    if (argc != 4) {
        std::cerr << "usage: make_fm7_basic_t77 <name> <program.bas> <out.t77>\n";
        return 2;
    }

    std::ifstream in(argv[2], std::ios::binary);
    if (!in) {
        std::cerr << "cannot read " << argv[2] << "\n";
        return 1;
    }
    std::vector<std::string> lines;
    for (std::string line; std::getline(in, line);)
        lines.push_back(line);
    // Build the normal FM-file (.0A0) wrapper first.  EncodeFromFMFile then
    // removes that wrapper and emits the corresponding T77 BASIC header/data
    // blocks, including the CR/LF records and 0x1A terminator expected by FM-7
    // cassette BASIC.
    auto fm7_data = FM7Lib::TextTo0A0(lines, argv[1]);

    T77Encoder encoder;
    if (!encoder.EncodeFromFMFile(argv[1], fm7_data)) {
        std::cerr << "T77 encoding failed\n";
        return 1;
    }

    std::ofstream out(argv[3], std::ios::binary);
    if (!out) {
        std::cerr << "cannot write " << argv[3] << "\n";
        return 1;
    }
    out.write(reinterpret_cast<const char *>(encoder.t77.data()),
              static_cast<std::streamsize>(encoder.t77.size()));
    std::cout << argv[3] << ": " << encoder.t77.size() << " bytes\n";
}

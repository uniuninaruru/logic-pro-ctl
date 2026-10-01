// Headless Ghidra post-script for targeted questions on an analyzed program.
//
//   analyzeHeadless <projDir> <projName> -process <program> -noanalysis -readOnly \
//     -scriptPath Tools/ghidra -postScript XrefDecompile.java <outFile> <query>...
//
// Queries:
//   0x<addr>      decompile the function containing addr
//   s:<text>      functions referencing a defined string that contains text
//   refs:0x<addr> functions referencing addr (directly or via one data pointer)
//   callers:<fn>  functions calling the function named fn (Ghidra name, e.g.
//                 RemoteCommandSupport::parseCommandQuery: or FUN_008663d4)
// Read-only. Output: one file with a header per query and the decompiled C.
// @category logicctl

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.data.StringDataInstance;
import ghidra.program.model.listing.Data;
import ghidra.program.model.listing.DataIterator;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.Symbol;

import java.io.File;
import java.io.PrintWriter;
import java.util.LinkedHashSet;
import java.util.Set;

public class XrefDecompile extends GhidraScript {
    private DecompInterface decomp;
    private PrintWriter out;

    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) {
            printerr("usage: XrefDecompile.java <outFile> <query>...");
            return;
        }
        decomp = new DecompInterface();
        decomp.openProgram(currentProgram);
        try (PrintWriter w = new PrintWriter(new File(args[0]), "UTF-8")) {
            out = w;
            for (int i = 1; i < args.length; i++) {
                String q = args[i];
                out.println("\n//////// QUERY " + q);
                Set<Function> fns = new LinkedHashSet<>();
                if (q.startsWith("0x")) {
                    Function f = getFunctionContaining(toAddr(q));
                    if (f != null) fns.add(f);
                } else if (q.startsWith("refs:")) {
                    collectRefs(toAddr(q.substring(5)), fns, 1);
                } else if (q.startsWith("s:")) {
                    String text = q.substring(2);
                    DataIterator it = currentProgram.getListing().getDefinedData(true);
                    while (it.hasNext() && !monitor.isCancelled()) {
                        Data d = it.next();
                        StringDataInstance s = StringDataInstance.getStringDataInstance(d);
                        if (s == StringDataInstance.NULL_INSTANCE) continue;
                        String v = s.getStringValue();
                        if (v == null || !v.contains(text)) continue;
                        out.println("// string @" + d.getAddress() + ": " + v);
                        collectRefs(d.getAddress(), fns, 2);
                    }
                } else if (q.startsWith("callers:")) {
                    String name = q.substring(8);
                    for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
                        if (!f.getName(true).equals(name)) continue;
                        out.println("// target " + name + " @" + f.getEntryPoint());
                        for (Reference r : getReferencesTo(f.getEntryPoint())) {
                            Function c = getFunctionContaining(r.getFromAddress());
                            if (c != null) fns.add(c);
                        }
                        // Objective-C methods are reached through selector strings too.
                        for (Symbol sym : currentProgram.getSymbolTable().getSymbols(f.getName())) {
                            collectRefs(sym.getAddress(), fns, 1);
                        }
                    }
                }
                out.println("// " + fns.size() + " function(s)");
                for (Function f : fns) emit(f);
            }
        } finally {
            decomp.dispose();
        }
        println("XrefDecompile: done -> " + args[0]);
    }

    /** Functions referencing addr, following data-to-data pointers up to depth. */
    private void collectRefs(Address addr, Set<Function> fns, int depth) {
        for (Reference r : getReferencesTo(addr)) {
            Function f = getFunctionContaining(r.getFromAddress());
            if (f != null) {
                fns.add(f);
            } else if (depth > 0) {
                collectRefs(r.getFromAddress(), fns, depth - 1);  // e.g. CFString -> cstring
            }
        }
    }

    private void emit(Function f) {
        out.println("\n// ==== " + f.getName(true) + " @ " + f.getEntryPoint());
        DecompileResults r = decomp.decompileFunction(f, 120, monitor);
        out.println(r != null && r.decompileCompleted() ? r.getDecompiledFunction().getC()
                                                        : "// decompilation failed");
    }
}

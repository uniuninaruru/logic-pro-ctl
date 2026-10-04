// Read-only: for each function, list the constants it copies into stack variables.
//
//   -postScript StackStoreReport.java <output.tsv> <function address>...
//
// A function that fills a table on its stack (Logic's command-group constructors) shows up in the
// decompiled C as `local_228 = &cf_OpenSetup;`. The label `cf_...` is lossy (spaces are dropped and
// UTF-16 strings are cut to one letter), so this reports the constant itself: the address.
//
// Output columns: function, stack offset (hex, negative), size, value (hex). No decompiled text,
// no type or label changes, nothing is sent to the application.
// @category logicctl

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.pcode.HighFunction;
import ghidra.program.model.pcode.PcodeOp;
import ghidra.program.model.pcode.PcodeOpAST;
import ghidra.program.model.pcode.Varnode;

import java.io.File;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.util.Iterator;

public class StackStoreReport extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) throw new IllegalArgumentException("usage: StackStoreReport.java <out.tsv> <address>...");
        DecompInterface decompiler = new DecompInterface();
        decompiler.openProgram(currentProgram);
        File output = new File(args[0]);
        File parent = output.getAbsoluteFile().getParentFile();
        if (parent != null) parent.mkdirs();
        int rows = 0;
        try (PrintWriter out = new PrintWriter(output, StandardCharsets.UTF_8)) {
            out.println("# Program: " + currentProgram.getName());
            out.println("# Imported executable SHA-256: " + currentProgram.getExecutableSHA256());
            out.println("# function\tstack_offset\tsize\tvalue\tsource");
            for (int i = 1; i < args.length; i++) {
                Function function = getFunctionContaining(toAddr(args[i]));
                if (function == null) { out.println("# no function at " + args[i]); continue; }
                DecompileResults results = decompiler.decompileFunction(function, 180, monitor);
                HighFunction high = results.getHighFunction();
                if (high == null) { out.println("# decompile failed: " + function.getName()); continue; }
                Iterator<PcodeOpAST> ops = high.getPcodeOps();
                while (ops.hasNext()) {
                    PcodeOpAST op = ops.next();
                    Varnode to = op.getOutput();
                    if (to == null || !to.getAddress().isStackAddress()) continue;
                    // A stack variable is set either by COPY from a constant, or (for a pointer
                    // to a CFString or a function) by a COPY/CAST of an address.
                    int code = op.getOpcode();
                    if (code != PcodeOp.COPY && code != PcodeOp.CAST && code != PcodeOp.PTRSUB) continue;
                    Varnode from = op.getInput(code == PcodeOp.PTRSUB ? 1 : 0);
                    if (!(from.isConstant() || from.isAddress())) continue;
                    out.println(function.getEntryPoint() + "\t0x" + Long.toHexString(to.getOffset()) + "\t"
                            + to.getSize() + "\t0x" + Long.toHexString(from.getOffset()) + "\t"
                            + PcodeOp.getMnemonic(code) + (from.isConstant() ? ":const" : ":addr"));
                    rows++;
                }
            }
        }
        println("StackStoreReport: " + rows + " rows -> " + output);
    }
}

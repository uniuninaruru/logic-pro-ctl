// Read-only machine-code/data report for SA-AE-STATE-002, Logic 12.3.1 (6682).
// analyzeHeadless <projects>/logicctl logicctl -process Logic.arm64 -noanalysis
//   -readOnly -scriptPath Tools/ghidra -postScript TransportStateReport.java <outFile>
// No decompiler type changes, target attachment, or runtime events.
// @category logicctl

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.data.StringDataInstance;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.Reference;
import java.io.File;
import java.io.PrintWriter;
import java.util.HexFormat;

public class TransportStateReport extends GhidraScript {
    private static final String SOURCE_SHA256 =
        "2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998";
    private static final String[] FUNCTIONS = {
        "014fc9d4", "014fca44", "014fcb04", "014fcd18", "014fcdd8",
        "0168f070", "0168fa54", "0168fad4", "0168f238", "0168f0dc",
        "01683acc", "016839d4", "01683ad8", "0168e1d4", "01699828",
        "011e0118", "00865cec", "010e3628", "00590e30",
        "01ba7f20", "01ba7fa0", "01b55f80", "01b1c480"
    };
    private static final String[] DATA = {
        "01e2a7ff", "01e2a831", "01dfd207", "01e2a777",
        "0240cae8", "0240cb28", "023cf0c8", "0256bb80", "0256bba0",
        "02557398", "02282358", "0242fd30", "0242fcb8"
    };

    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length != 1) throw new IllegalArgumentException("Expected output file");
        if (!"Logic.arm64".equals(currentProgram.getName()) ||
            !SOURCE_SHA256.equalsIgnoreCase(currentProgram.getExecutableSHA256()))
            throw new IllegalArgumentException("Wrong source program/hash; re-identify anchors first");
        File output = new File(args[0]);
        File parent = output.getAbsoluteFile().getParentFile();
        if (parent != null) parent.mkdirs();
        try (PrintWriter out = new PrintWriter(output, "UTF-8")) {
            out.println("# Program: " + currentProgram.getName());
            out.println("# Executable: " + currentProgram.getExecutablePath());
            out.println("# SHA-256: " + currentProgram.getExecutableSHA256());
            out.println("# Machine bytes and data only; semantic conclusions are in SA-AE-STATE-002.");
            for (String anchor : FUNCTIONS) {
                Function function = getFunctionAt(toAddr(anchor));
                if (function == null) throw new IllegalArgumentException("Missing function " + anchor);
                out.println("\n# " + function.getName(true) + " @ " + function.getEntryPoint());
                for (Instruction instruction : currentProgram.getListing().getInstructions(function.getBody(), true)) {
                    out.println(instruction.getAddress() + "\t" +
                        HexFormat.of().formatHex(instruction.getBytes()) + "\t" + instruction);
                }
            }
            for (String anchor : DATA) {
                Address address = toAddr(anchor);
                byte[] bytes = new byte[32];
                currentProgram.getMemory().getBytes(address, bytes);
                out.println("\n# Data @ " + address + ": " + HexFormat.of().formatHex(bytes));
                Data data = currentProgram.getListing().getDefinedDataAt(address);
                if (data != null) {
                    out.println("# " + data.getDataType().getName() + ": " + data.getDefaultValueRepresentation());
                    StringDataInstance text = StringDataInstance.getStringDataInstance(data);
                    if (text != StringDataInstance.NULL_INSTANCE)
                        out.println("# String: " + text.getStringValue());
                    for (int index = 0; index < data.getNumComponents(); index++) {
                        Data component = data.getComponent(index);
                        out.println("# Component " + component.getAddress() + ": " + component.getDefaultValueRepresentation());
                    }
                }
                for (Reference reference : getReferencesTo(address))
                    out.println("# Ref " + reference.getFromAddress() + " " + reference.getReferenceType());
            }
        }
        println("TransportStateReport: exported " + output.getAbsolutePath());
    }
}

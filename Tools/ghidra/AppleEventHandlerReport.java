// Read-only, version-specific Logic 12.3.1 arm64 AppleEvent report.
// Run with analyzeHeadless -process Logic.arm64 -noanalysis -readOnly
//   -scriptPath Tools/ghidra -postScript AppleEventHandlerReport.java <outDirectory>
// Function signatures are corrected in memory for this export only; readOnly
// prevents committing analysis changes. No target app is loaded or modified.
// @category logicctl

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.data.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.SourceType;
import java.io.File;
import java.io.PrintWriter;
import java.util.*;

public class AppleEventHandlerReport extends GhidraScript {
    private static final String SOURCE_SHA256 =
        "2f141e1a1f7b90a4fb0205ffec3dbe187baf601d20e9acb398acfadcdf050998";
    private DataType ose, size, u32, byteType, voidType, pointer, eventPointer;
    private PrintWriter signatures;

    private DataType alias(String name, DataType base) {
        return new TypedefDataType(new CategoryPath("/AppleEventsResearch"), name, base,
                                   currentProgram.getDataTypeManager());
    }

    private DataType ptr(DataType base) {
        return new PointerDataType(base, 8, currentProgram.getDataTypeManager());
    }

    private void signature(Function function, DataType result, String[] names,
                           DataType... types) throws Exception {
        if (function == null) throw new IllegalArgumentException("Missing anchor function");
        function.setCallingConvention(currentProgram.getCompilerSpec().getDefaultCallingConvention().getName());
        function.setReturnType(result, SourceType.USER_DEFINED);
        Parameter[] parameters = new Parameter[types.length];
        for (int i = 0; i < types.length; i++)
            parameters[i] = new ParameterImpl(names[i], types[i], currentProgram);
        function.replaceParameters(Function.FunctionUpdateType.DYNAMIC_STORAGE_ALL_PARAMS,
                                   true, SourceType.USER_DEFINED, parameters);
        function.setVarArgs(false);
        if (signatures != null)
            signatures.println(function.getEntryPoint() + "\t" + function.getPrototypeString(false, false));
    }

    private Function at(String address) {
        return getFunctionAt(toAddr(address));
    }

    private void imported(String name, DataType result, String[] names,
                          DataType... types) throws Exception {
        int matches = 0;
        for (Function function : currentProgram.getFunctionManager().getFunctions(true)) {
            if (function.getName().equals(name)) {
                signature(function, result, names, types);
                matches++;
            }
        }
        if (matches == 0) signatures.println("MISSING\t" + name);
    }

    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length != 1) throw new IllegalArgumentException("Expected output directory");
        if (!"Logic.arm64".equals(currentProgram.getName()) ||
            !SOURCE_SHA256.equalsIgnoreCase(currentProgram.getExecutableSHA256()))
            throw new IllegalArgumentException("Wrong source program/hash; re-identify anchors first");
        File directory = new File(args[0]);
        directory.mkdirs();
        voidType = VoidDataType.dataType;
        u32 = UnsignedIntegerDataType.dataType;
        byteType = UnsignedCharDataType.dataType;
        pointer = ptr(voidType);
        ose = alias("OSErr", ShortDataType.dataType);
        // macOS arm64 LP64: MacTypes.h typedef long Size; typedef void* SRefCon.
        size = alias("Size", LongLongDataType.dataType);
        DataType descType = alias("DescType", u32);
        DataType keyword = alias("AEKeyword", u32);
        DataType refcon = alias("SRefCon", pointer);
        StructureDataType event = new StructureDataType(new CategoryPath("/AppleEventsResearch"),
                                                        "AppleEvent", 0,
                                                        currentProgram.getDataTypeManager());
        // AEDataModel.h pragma pack(push, 2): AEDesc is UInt32 + 8-byte handle.
        event.add(descType, 4, "descriptorType", null);
        event.add(pointer, 8, "dataHandle", null);
        eventPointer = ptr(event);
        FunctionDefinitionDataType callback = new FunctionDefinitionDataType(
            new CategoryPath("/AppleEventsResearch"), "AEEventHandlerProcPtr",
            currentProgram.getDataTypeManager());
        callback.setReturnType(ose);
        callback.setArguments(new ParameterDefinition[] {
            new ParameterDefinitionImpl("event", eventPointer, null),
            new ParameterDefinitionImpl("reply", eventPointer, null),
            new ParameterDefinitionImpl("handlerRefcon", refcon, null)});

        try (PrintWriter writer = new PrintWriter(new File(directory, "corrected-signatures.tsv"), "UTF-8")) {
            signatures = writer;
            writer.println("# Program: " + currentProgram.getName() + "; SHA-256: " + currentProgram.getExecutableSHA256());
            writer.println("# Local SDK source: CoreServices/AE.framework/Headers/{AppleEvents.h,AEDataModel.h}; usr/include/MacTypes.h");
            writer.println("# OSErr=2 bytes, DescType/AEKeyword=4 bytes, Size=8 bytes, SRefCon=8 bytes; AEDesc=12 bytes under pack(2)");
            imported("_AEInstallEventHandler", ose,
                     new String[]{"eventClass", "eventID", "handler", "handlerRefcon", "isSystemHandler"},
                     u32, u32, ptr(callback), refcon, byteType);
            imported("_AESizeOfParam", ose,
                     new String[]{"event", "keyword", "actualType", "dataSize"},
                     eventPointer, keyword, ptr(descType), ptr(size));
            imported("_AEGetParamPtr", ose,
                     new String[]{"event", "keyword", "desiredType", "actualType", "data", "maximumSize", "actualSize"},
                     eventPointer, keyword, descType, ptr(descType), pointer, size, ptr(size));
            imported("_AEPutParamPtr", ose,
                     new String[]{"reply", "keyword", "type", "data", "dataSize"},
                     eventPointer, keyword, descType, pointer, size);
            imported("_malloc", pointer, new String[]{"size"}, UnsignedLongLongDataType.dataType);
            imported("_free", voidType, new String[]{"allocation"}, pointer);
            imported("___cxa_guard_acquire", IntegerDataType.dataType, new String[]{"guard"}, pointer);
            imported("___cxa_guard_release", voidType, new String[]{"guard"}, pointer);
            imported("___cxa_atexit", IntegerDataType.dataType,
                     new String[]{"destructor", "object", "dso"}, pointer, pointer, pointer);
            imported("_CFStringCreateWithCharacters", pointer,
                     new String[]{"allocator", "characters", "count"}, pointer, pointer, size);
            imported("_CFStringCreateWithBytes", pointer,
                     new String[]{"allocator", "bytes", "count", "encoding", "externalRepresentation"},
                     pointer, pointer, size, u32, byteType);
            imported("_CFRelease", voidType, new String[]{"object"}, pointer);
            imported("_CFStringGetLength", size, new String[]{"string"}, pointer);
            imported("_CFStringGetMaximumSizeForEncoding", size,
                     new String[]{"length", "encoding"}, size, u32);
            imported("_CFStringGetBytes", size,
                     new String[]{"string", "rangeLocation", "rangeLength", "encoding", "lossByte", "externalRepresentation", "buffer", "maxLength", "usedLength"},
                     pointer, size, size, u32, byteType, byteType, pointer, size, ptr(size));
            imported("_CFStringGetPascalString", byteType,
                     new String[]{"string", "buffer", "bufferSize", "encoding"}, pointer, pointer, size, u32);
            imported("_CFStringGetSystemEncoding", u32, new String[]{});
            // Version-specific application functions: machine code proves these
            // call arguments; semantic class/type of owner remains unresolved.
            signature(at("00590e30"), ose,
                      new String[]{"event", "reply", "handlerRefcon"}, eventPointer, eventPointer, refcon);
            signature(at("00591d08"), voidType, new String[]{});
            signature(at("008663d4"), voidType,
                      new String[]{"command", "ownerState", "arg2", "source", "arg4"},
                      ShortDataType.dataType, pointer, u32, u32, pointer);
            signature(at("01af1c90"), voidType, new String[]{"thisObject"}, pointer);
            signature(at("003b1c58"), IntegerDataType.dataType, new String[]{"song"}, pointer);
            signature(at("01079a2c"), pointer, new String[]{"song", "value"}, pointer, IntegerDataType.dataType);
            signature(at("019ae630"), pointer, new String[]{"song", "kind", "index", "flags"},
                      pointer, IntegerDataType.dataType, u32, u32);
            signature(at("010e3628"), IntegerDataType.dataType,
                      new String[]{"song", "value", "flags"}, pointer, LongLongDataType.dataType, u32);
        }
        signatures = null;

        DecompInterface decompiler = new DecompInterface();
        decompiler.openProgram(currentProgram);
        try (PrintWriter writer = new PrintWriter(new File(directory, "typed-decompiled.c"), "UTF-8")) {
            writer.println("// Export with corrected local SDK API signatures; edits are transient (-readOnly).");
            writer.println("// Remaining unknown C++ and ObjC signatures are not resolved by this report.");
            for (String address : new String[]{"004f0d24", "00590e30", "00591d08", "017ccab8", "008663d4"}) {
                Function function = at(address);
                writer.println("\n// ==== " + function.getName(true) + " @ " + function.getEntryPoint());
                DecompileResults result = decompiler.decompileFunction(function, 120, monitor);
                writer.println(result.decompileCompleted() ? result.getDecompiledFunction().getC()
                                                         : "// FAILED: " + result.getErrorMessage());
            }
        } finally { decompiler.dispose(); }

        // A second explicitly marked rendering models the 32-bit w0 register
        // tested by these callers. SDK OSErr remains short in the manifest above;
        // this alias is an ABI rendering aid, not a replacement SDK declaration.
        DataType oseRegister = alias("OSErr_W0_register", IntegerDataType.dataType);
        for (Function function : currentProgram.getFunctionManager().getFunctions(true)) {
            if (Arrays.asList("_AEInstallEventHandler", "_AESizeOfParam", "_AEGetParamPtr", "_AEPutParamPtr")
                      .contains(function.getName()))
                function.setReturnType(oseRegister, SourceType.USER_DEFINED);
        }
        DecompInterface normalized = new DecompInterface();
        normalized.openProgram(currentProgram);
        try (PrintWriter writer = new PrintWriter(new File(directory, "abi-normalized-decompiled.c"), "UTF-8")) {
            writer.println("// Imported AE API result types model 32-bit w0 tests, while SDK OSErr is short16.");
            writer.println("// Correct SDK declarations are retained in corrected-signatures.tsv and typed-decompiled.c.");
            writer.println("// This transient ABI rendering avoids Ghidra unknown upper bits/CONCAT artifacts.");
            for (String address : new String[]{"00590e30", "00591d08", "0168bba4", "0146f914"}) {
                Function function = at(address);
                writer.println("\n// ==== " + function.getName(true) + " @ " + function.getEntryPoint());
                DecompileResults result = normalized.decompileFunction(function, 120, monitor);
                writer.println(result.decompileCompleted() ? result.getDecompiledFunction().getC()
                                                         : "// FAILED: " + result.getErrorMessage());
            }
        } finally { normalized.dispose(); }

        try (PrintWriter writer = new PrintWriter(new File(directory, "owner-state-xrefs.tsv"), "UTF-8")) {
            writer.println("# Exact Ghidra references to global 0x0276de68; not a complete runtime data-flow analysis.");
            writer.println("source\treference_type\tfunction_entry\tfunction\tinstruction");
            for (Reference reference : getReferencesTo(toAddr("0276de68"))) {
                Address source = reference.getFromAddress();
                Function function = getFunctionContaining(source);
                Instruction instruction = getInstructionAt(source);
                writer.println(source + "\t" + reference.getReferenceType() + "\t" +
                    (function == null ? "" : function.getEntryPoint()) + "\t" +
                    (function == null ? "" : function.getName(true)) + "\t" +
                    (instruction == null ? "" : instruction.toString()));
            }
        }
        println("AppleEventHandlerReport: exported " + directory);
    }
}

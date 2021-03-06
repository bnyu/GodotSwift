//
//  BuiltinBind.swift
//  GodotSwift
//
//  Created by Miguel de Icaza on 2/1/21.
//  Copyright © 2021 Miguel de Icaza. MIT Licensed
//

import Foundation

func builtinBind (start: GodotBuiltinApi)
{
    var res = setupResult()
    
    for x in start {
        if !singleFile {
            res = setupResult()
        }
        let typeName = x.name
        if typeName == "Utilities" {
            // generate something later
            continue
        }
        if !isCoreType(name: typeName) {
            print ("BuiltinType: Skipping type \(typeName)")
            continue
        }
        // print ("type: \(x.name)")
        
        res += "public class \(x.name) {\n"
        let gdname = builtinTypeToGdName (typeName)
        let typeEnum = builtinTypeToGdNativeEnum (typeName)
        res += indent ("var _\(gdname): \(gdname) = \(gdname)()\n")
        
        res += indent ("init (_ native: \(gdname)) {\n")
        res += indent ("    _\(gdname) = native\n")
        res += indent ("}\n\n")
        
        // For String and StringName, make constructors that take Swift Strings
        if typeName == "String" {
            res += indent ("public init (_ str: Swift.String){\n")
            res += indent ("    \(gdname)_new_with_utf8_chars (&_\(gdname), str);\n")
            res += indent ("}\n")
        }
        res += indent (generateBuiltinConstants (x.constants, gdname, typeName, typeEnum))
        res += indent (generateBuiltinCtors (x.constructors, gdname, typeName, typeEnum))
        res += indent (generateBuiltinMethods (x.methods, gdname, typeName, typeEnum))
        res += indent (generateBuiltinMembers (x.members, gdname, typeName, typeEnum))
        res += indent (generateBuiltinOperators (x.operators, gdname, typeName, typeEnum))
        res += "}\n\n"
        
        if !singleFile {
            try! res.write(toFile: "\(outputDir)/\(typeName).gen.swift", atomically: true, encoding: .utf8)
        }
    }
    if singleFile {
        try! res.write(toFile: "\(outputDir)/builtins.gen.swift", atomically: true, encoding: .utf8)
    }
}


func generateBuiltinConstants (_ constants: [BConstant], _ gdname: String, _ typeName: String, _ typeEnum: String) -> String
{
    var generated = ""

    if constants.count > 0 {
        generated += "\n/* Constants */\n"
    }
    for c in constants {
        var mr = ""
        
        let constType = getGodotType (c.type.rawValue)
        mr += "public static var \(c.name): \(constType) = {\n"
        mr += "   var constant = godot_variant_get_constant_value_with_cstring (\(typeEnum), \"\(c.name)\")\n"
        let snakeType = camelToSnake(constType)
        mr += "   defer { godot_variant_destroy (&constant) }\n"
        mr += "   return \(constType) (godot_variant_as_\(snakeType) (&constant))\n"
        mr += "} ()\n"
        generated += mr
    }
    return generated
}

func generateBuiltinMethods (_ methods: [BConstructor], _ gdname: String, _ typeName: String, _ typeEnum: String) -> String
{
    var generated = ""
    if methods.count > 0 {
        generated += "\n/* Methods */\n"
    }
    for m in methods {
        var mr: String
        let ret = getGodotType(m.returnType)
        
        // TODO: problem caused by gobject_object being defined as "void", so it is not possible to create storage to that.
        if ret == "Object" {
            continue
        }
        let retSig = ret == "" ? "" : "-> \(ret)"
        var args = ""
    
        let ptrName = "method_\(m.name)"
        mr = "static var \(ptrName): godot_ptr_builtin_method = godot_variant_get_ptr_builtin_method_with_cstring (\(typeEnum), \"\(m.name)\")\n"
        for arg in m.arguments {
            if args != "" { args += ", " }
            args += getArgumentDeclaration(arg, eliminate: "")
        }
        
        let has_return = m.returnType != "void"
        
        mr += "public func \(escapeSwift (snakeToCamel(m.name))) (\(args))\(retSig) {\n"
        var body = ""
        let resultTypeName = builtinTypeToGdName(m.returnType)
        body += (has_return ? "var result: \(resultTypeName) = \(resultTypeName)()" : "") + "\n"
        
        let (argPrep, warnDelete) = generateArgPrepare(m.arguments)
        body += argPrep
        let ptrArgs = m.arguments.count > 0 ? "&args" : "nil"
        let ptrResult = has_return ? "&result" : "nil"
        
        body += "\(typeName).\(ptrName) (&_\(gdname), \(ptrArgs), \(ptrResult), \(m.arguments.count))"
        body += "\n"
        if has_return {
            let cast = castGodotToSwift (m.returnType, "result")
            body += "return \(cast)"
        }
        mr += indent (body)
        mr += warnDelete
        mr += "}\n"
        generated += mr
    }
    return generated
}

func generateBuiltinOperators (_ operators: [BOperator], _ gdname: String, _ typeName: String, _ typeEnum: String) -> String
{
    var generated = ""
    if operators.count > 0 {
        generated += "\n/* Operators */\n"
    }
    for op in operators {
        var mr = ""
        let code = op.operatorOperator
        let rightEnum = builtinTypeToGdNativeEnum (op.otherType)
        
        if getOperatorName(code: op.operatorOperator) == "in" {
            // TODO: figure out operator "in" later
            continue;
        }
        mr += "static var op_\(code)_\(op.otherType): godot_ptr_operator_evaluator = godot_variant_get_ptr_operator_evaluator (godot_variant_operator(\(code)), \(typeEnum), \(rightEnum))\n"
        mr += "public static func \(getOperatorName (code: op.operatorOperator)) (left: \(typeName), right: \(getGodotType (op.otherType))) -> \(getGodotType (op.returnType)) {\n"
        let resultTypeName = builtinTypeToGdName(op.returnType)
        var right: String
        if isCoreType(name: op.otherType) {
            right = "right._\(builtinTypeToGdName(op.otherType))"
        } else {
            right = "copy"
            mr += "    var copy = right\n"
        }
        mr += "    var result: \(resultTypeName) = \(resultTypeName)()\n"
        mr += "    op_\(code)_\(op.otherType) (&left._\(gdname), &\(right), &result)\n"
        mr += "    return \(castGodotToSwift (op.returnType, "result"))\n"
        mr += "}\n"
        
        generated += mr
    }
    return generated
}

func generateBuiltinMembers (_ members: [BMember], _ gdname: String, _ typeName: String, _ typeEnum: String) -> String
{
    var generated = ""
    if members.count > 0 {
        generated += "\n/* Properties */\n"
    }

    for m in members {
        var mr = ""
        let name = m.name
        let memberType = getGodotType (m.type.rawValue)
        let resultTypeName = builtinTypeToGdName(m.type.rawValue)
        mr += "static var get_\(name): godot_ptr_getter = godot_variant_get_ptr_getter_with_cstring (\(typeEnum), \"\(m.name)\")\n"
        mr += "static var set_\(name): godot_ptr_setter = godot_variant_get_ptr_setter_with_cstring (\(typeEnum), \"\(m.name)\")\n"
        mr += "public var \(name): \(memberType) {\n"
        mr += "    get {\n"
        mr += "        var result: \(resultTypeName) = \(resultTypeName)()\n"
        mr += "        \(typeName).get_\(name) (&_\(gdname), &result)\n"
        let cast = castGodotToSwift(m.type.rawValue, "result")
        mr += "        return \(cast)\n"
        mr += "    }\n"
        mr += "    set {\n"
        var arg: String
        if !isCoreType (name: m.type.rawValue) {
            mr += "        var copy = newValue\n"
            arg = "copy"
        } else {
            let argType = builtinTypeToGdName(m.type.rawValue)
            arg = "newValue._\(argType)"
        }
        mr += "        \(typeName).set_\(name) (&_\(gdname), &\(arg))\n"
        mr += "        abort()\n"
        mr += "    }\n"
        mr += "}\n"

        generated += mr
    }
    return generated
}

func generateBuiltinCtors (_ methods: [BConstructor], _ gdname: String, _ typeName: String, _ typeEnum: String) -> String
{
    var generated = ""
    var ctorCount = 0
    for m in methods {
        var mr: String
        
        var args = ""
    
        let ptrName = "constructor\(ctorCount)"
        mr = "static var \(ptrName): godot_ptr_constructor = godot_variant_get_ptr_constructor (\(typeEnum), \(ctorCount))\n"
        ctorCount += 1
        for arg in m.arguments {
            if args != "" { args += ", " }
            args += getArgumentDeclaration(arg, eliminate: "")
        }
        
        mr += "public init (\(args)) {\n"
        var body = ""
        
        let (argPrep, warnDelete) = generateArgPrepare(m.arguments)
        body += argPrep

        let ptrArgs = m.arguments.count > 0 ? "&args" : "nil"
        
        body += "\(typeName).\(ptrName) (&_\(gdname), \(ptrArgs))"
        body += "\n"
        mr += indent (body)
        mr += warnDelete
        mr += "}\n"
        generated += mr
    }
    return generated
}

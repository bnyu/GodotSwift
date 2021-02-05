//
//  genMain.swift
//  GodotSwift
//
//  Created by Miguel de Icaza on 2/3/21.
//  Copyright © 2021 Miguel de Icaza. All rights reserved.
//

import Foundation

var referenceTypes: [String:Bool] = [:]
var tree: [String:WelcomeElement] = [:]

func isOverride (_ member: String, on: String) -> Bool {
    guard var current = tree [on] else {
        return false
    }
    while true {
        guard let base = tree [current.baseClass] else {
            return false
        }
        for m in base.methods {
            if m.name == member {
                return true
            }
        }
        current = base
    }
}

func genBind (start: GodotApi)
{
    // Assemble all the reference types, we use to test later
    for x in start {
        referenceTypes[stripName (x.name)] = true
    }
    for x in start {
        tree [x.name] = x
    }
    
    for x in start {
        var res = """
    // Generated by GodotSwift code generator
    import Foundation
    import Godot

    """

        let typeName = stripName (x.name)
        //print ("General: \(typeName)")
//        if !(typeName == "Object" || typeName == "Reference" || typeName == "Engine" || typeName == "MainLoop") {
//            continue
//        }
        let baseClass = x.baseClass == "" ? "Wrapped" : stripName(x.baseClass)
        res += "public class \(typeName):  \(baseClass) {\n"
        let gdname = builtinTypeToGdName (typeName)
        let typeEnum = builtinTypeToGdNativeEnum (typeName)
        
        
        res += indent ("override init (nativeHandle: UnsafeRawPointer) {\n")
        res += indent ("    super.init (nativeHandle: nativeHandle)\n")
        res += indent ("}\n\n")
        
        //res += indent (generateMainConstants (x.constants, gdname, typeName, typeEnum))
        //res += indent (generateMainCtors (x.constructors, gdname, typeName, typeEnum))
        res += indent (generateMainMethods (x.methods, gdname, typeName, x.name, typeEnum))
        res += indent (generateEnums (x.enums))
        //res += indent (generateMainMembers (x.members, gdname, typeName, typeEnum))
        //res += indent (generateMainOperators (x.operators, gdname, typeName, typeEnum))
        res += "}\n\n"
        
        try! res.write(toFile: "/Users/miguel/cvs/GodotSwiftLink/Sources/GodotSwift/generated/\(typeName).gen.swift", atomically: true, encoding: .utf8)
    }
}

// Returns an ideal prefix that should be dropped from enumeration keys,
// based on assorted heuristics
func getDropPrefix (_ e: Enum) -> String
{
    // For an enum type MyType it will attempt to drop
    // MY_TYPE, MY, TYPE.   Then it also attempts for
    // scenarios where the type ends in "Mode" to drop
    // the "Mode" prefix, and same for Flag
    var prefixes = camelToSnake(e.name).split(separator: "_").map {String ($0).uppercased()}
    prefixes.insert(camelToSnake (e.name).uppercased(), at: 0)
    if e.name.hasSuffix("Mode") {
        let drop = String (e.name.dropLast (4))
        
        prefixes.insert (camelToSnake (drop).uppercased(), at: 1)
    }
    if e.name.hasSuffix ("Flags") {
        prefixes.insert ("FLAG", at: 1)
    }
    for prefix in prefixes {
        var failed = false
        for entry in e.values {
            if !entry.key.starts(with: prefix + "_") {
                failed = true
                break
            }
        }
        if !failed {
            //print ("Found prefix for \(e.name) to be \(prefix)")
            return prefix + "_"
        }
    }
    return ""
}

func generateEnums (_ enums: [Enum]) -> String
{
    var generated = ""
    if enums.count > 0 {
        generated += "\n/* Enumerations */\n\n"
    }
    for e in enums {
        var mr: String = ""
        var ename = e.name == "Type" ? "GType" : e.name
        
        mr += "public enum \(ename): Int {\n"
        //print ("enum \(e.name)")
        let drop = getDropPrefix(e)
        //let tsnake = camelToSnake(e.name)
        
        // Godot has a handful of aliases, and Swift does not like that
        // we pick the first
        var seenValues = Set<Int> ()
        for v in e.values {
            if seenValues.contains(v.value) {
                continue
            }
            seenValues.insert(v.value)
            var k = v.key
            k = snakeToCamel(String (k.dropFirst(drop.count)))
            if k.first!.isNumber {
                k = e.name.first!.lowercased() + k
            }
            
            //print ("   enum \(v.key) -> \(k)")
            mr += "    case \(escapeSwift (k)) = \(v.value)\n"
        }
//        if e.name.contains("Flag") {
//            print (mr)
//        }
        mr += "}\n\n"
        generated += mr
    }
    return generated
}
func generateMainMethods (_ methods: [Method], _ gdname: String, _ typeName: String, _ originalTypeName: String, _ typeEnum: String) -> String
{
    var generated = ""
    if methods.count > 0 {
        generated += "\n/* Methods */\n"
    }
    var n = 0
    for m in methods {
        var mr: String
        let ret = getGodotType(m.returnType)

        // This is referenced, but does not exist?
        if m.returnType == ("enum.Vector3::Axis") {
            continue
        }
        n += 1
        if n == 1000 {
            //break
        }
        let retSig = ret == "" ? "" : "-> \(ret)"
        var args = ""

        let ptrName = "method_\(m.name)"
        mr = "private static var \(ptrName): UnsafeMutablePointer<godot_method_bind> = godot_method_bind_get_method (\"\(originalTypeName)\", \"\(m.name)\")!\n"
        for arg in m.arguments {
            if args != "" { args += ", " }
            args += getArgumentDeclaration(arg)
        }

        let has_return = m.returnType != "void"

        var override = ""
        
        // Override lookup is expensive, as it scans methods one by one in an array
        // so limit the damager
        if m.name == "get_name" || m.name == "_unhandledInput" || m.name == "_input"  {
            if isOverride(m.name, on: typeName) {
                override = "override "
            }
        }
        
        mr += "public \(override)func \(escapeSwift (snakeToCamel(m.name))) (\(args))\(retSig) {\n"
        var body = ""
        let resultTypeName = builtinTypeToGdName(m.returnType)
        if isCoreType(name: m.returnType) {
            body += (has_return ? "var _result: \(resultTypeName) = \(resultTypeName)()" : "") + "\n"
        } else {
            body += (has_return ? "var _result: Int = 0" : "") + "\n"
        }

        let (argPrep, warnDelete) = generateArgPrepare(m.arguments)
        body += argPrep
        let ptrArgs = m.arguments.count > 0 ? "&args" : "nil"
        let ptrResult = has_return ? "&_result" : "nil"

        body += "miguel_proxy (\(typeName).\(ptrName), handle, \(ptrArgs), \(ptrResult))"
        body += "\n"
        if has_return {
            if let _ = referenceTypes [m.returnType] {
                body += "return \(m.returnType) (nativeHandle: UnsafeRawPointer (bitPattern: _result)!)\n"
            } else {
                let cast = castGodotToSwift (m.returnType, "_result")
                body += "return \(cast) /* \(m.returnType) */\n"
            }
        }
        mr += indent (body)
        mr += warnDelete
        mr += "}\n"
        generated += mr
        
    }
    return generated
}

//
//func generateMainConstants (_ constants: [BConstant], _ gdname: String, _ typeName: String, _ typeEnum: String) -> String
//{
//    var generated = ""
//
//    if constants.count > 0 {
//        generated += "\n/* Constants */\n"
//    }
//    for c in constants {
//        var mr = ""
//
//        var constType = getGodotType (c.type.rawValue)
//        mr += "public static var \(c.name): \(constType) = {\n"
//        mr += "   var constant = godot_variant_get_constant_value_with_cstring (\(typeEnum), \"\(c.name)\")\n"
//        let snakeType = camelToSnake(constType)
//        mr += "   defer { godot_variant_destroy (&constant) }\n"
//        mr += "   return \(constType) (godot_variant_as_\(snakeType) (&constant))\n"
//        mr += "} ()\n"
//        generated += mr
//    }
//    return generated
//}
//

//func generateMainOperators (_ operators: [BOperator], _ gdname: String, _ typeName: String, _ typeEnum: String) -> String
//{
//    var generated = ""
//    if operators.count > 0 {
//        generated += "\n/* Operators */\n"
//    }
//    for op in operators {
//        var mr = ""
//        let code = op.operatorOperator
//        let rightEnum = builtinTypeToGdNativeEnum (op.otherType)
//        let name = op.name
//        if getOperatorName(code: op.operatorOperator) == "in" {
//            // TODO: figure out operator "in" later
//            continue;
//        }
//        mr += "static var op_\(code)_\(op.otherType): godot_ptr_operator_evaluator = godot_variant_get_ptr_operator_evaluator (godot_variant_operator(\(code)), \(typeEnum), \(rightEnum))\n"
//        mr += "public static func \(getOperatorName (code: op.operatorOperator)) (left: \(typeName), right: \(getGodotType (op.otherType))) -> \(getGodotType (op.returnType)) {\n"
//        var resultTypeName = builtinTypeToGdName(op.returnType)
//        var right: String
//        if isCoreType(name: op.otherType) {
//            right = "right._\(builtinTypeToGdName(op.otherType))"
//        } else {
//            right = "copy"
//            mr += "    var copy = right\n"
//        }
//        mr += "    var result: \(resultTypeName) = \(resultTypeName)()\n"
//        mr += "    op_\(code)_\(op.otherType) (&left._\(gdname), &\(right), &result)\n"
//        mr += "    return \(castGodotToSwift (op.returnType, "result"))\n"
//        mr += "}\n"
//
//        generated += mr
//    }
//    return generated
//}
//
//func generateMainMembers (_ members: [BMember], _ gdname: String, _ typeName: String, _ typeEnum: String) -> String
//{
//    var generated = ""
//    if members.count > 0 {
//        generated += "\n/* Properties */\n"
//    }
//
//    for m in members {
//        var mr = ""
//        let name = m.name
//        let memberType = getGodotType (m.type.rawValue)
//        var resultTypeName = builtinTypeToGdName(m.type.rawValue)
//        mr += "static var get_\(name): godot_ptr_getter = godot_variant_get_ptr_getter_with_cstring (\(typeEnum), \"\(m.name)\")\n"
//        mr += "static var set_\(name): godot_ptr_setter = godot_variant_get_ptr_setter_with_cstring (\(typeEnum), \"\(m.name)\")\n"
//        mr += "public var \(name): \(memberType) {\n"
//        mr += "    get {\n"
//        mr += "        var result: \(resultTypeName) = \(resultTypeName)()\n"
//        mr += "        \(typeName).get_\(name) (&_\(gdname), &result)\n"
//        let cast = castGodotToSwift(m.type.rawValue, "result")
//        mr += "        return \(cast)\n"
//        mr += "    }\n"
//        mr += "    set {\n"
//        var arg: String
//        if !isCoreType (name: m.type.rawValue) {
//            mr += "        var copy = newValue\n"
//            arg = "copy"
//        } else {
//            let argType = builtinTypeToGdName(m.type.rawValue)
//            arg = "newValue._\(argType)"
//        }
//        mr += "        \(typeName).set_\(name) (&_\(gdname), &\(arg))\n"
//        mr += "        abort()\n"
//        mr += "    }\n"
//        mr += "}\n"
//
//        generated += mr
//    }
//    return generated
//}
//
//func generateMainCtors (_ methods: [BConstructor], _ gdname: String, _ typeName: String, _ typeEnum: String) -> String
//{
//    var generated = ""
//    var ctorCount = 0
//    for m in methods {
//        var mr: String
//
//        var args = ""
//
//        let ptrName = "constructor\(ctorCount)"
//        mr = "static var \(ptrName): godot_ptr_constructor = godot_variant_get_ptr_constructor (\(typeEnum), \(ctorCount))\n"
//        ctorCount += 1
//        for arg in m.arguments {
//            if args != "" { args += ", " }
//            args += getArgumentDeclaration(arg)
//        }
//
//        mr += "public init (\(args)) {\n"
//        var body = ""
//
//        let (argPrep, warnDelete) = generateArgPrepare(m.arguments)
//        body += argPrep
//
//        let ptrArgs = m.arguments.count > 0 ? "&args" : "nil"
//
//        body += "\(typeName).\(ptrName) (&_\(gdname), \(ptrArgs))"
//        body += "\n"
//        mr += indent (body)
//        mr += warnDelete
//        mr += "}\n"
//        generated += mr
//    }
//    return generated
//}

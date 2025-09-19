import CLua

open class Number: StoredValue, CustomDebugStringConvertible {
    
    override open func kind() -> Kind { return .number }
    
    open func toDouble() -> Double {
        push(vm)
        let v = lua_tonumberx(vm.state, -1, nil)
        vm.pop()
        return v
    }
    
    open func toInteger() -> Int64 {
        push(vm)
        let v = lua_tointegerx(vm.state, -1, nil)
        vm.pop()
        return v
    }
    
    open var debugDescription: String {
        push(vm)
        let isInteger = lua_isinteger(vm.state, -1) != 0
        vm.pop()
        
        if isInteger { return toInteger().description }
        else { return toDouble().description }
    }
    
    open var isInteger: Bool {
        push(vm)
        let isInteger = lua_isinteger(vm.state, -1) != 0
        vm.pop()
        return isInteger
    }
    
    override open class func arg(_ vm: VirtualMachine, value: Value) -> String? {
        if value.kind() != .number { return "number" }
        return nil
    }
    
}

extension Double: Value {
    
    public func push(_ vm: VirtualMachine) {
        lua_pushnumber(vm.state, self)
    }
    
    public func kind() -> Kind { return .number }
    
    public static func arg(_ vm: VirtualMachine, value: Value) -> String? {
        value.push(vm)
        let isDouble = lua_isinteger(vm.state, -1) != 0
        vm.pop()
        if !isDouble { return "double" }
        return nil
    }
    
}

extension Int64: Value {
    
    public func push(_ vm: VirtualMachine) {
        lua_pushinteger(vm.state, self)
    }
    
    public func kind() -> Kind { return .number }
    
    public static func arg(_ vm: VirtualMachine, value: Value) -> String? {
        value.push(vm)
        let isDouble = lua_isinteger(vm.state, -1) != 0
        vm.pop()
        if !isDouble { return "integer" }
        return nil
    }
    
}

extension Int: Value {
    
    public func push(_ vm: VirtualMachine) {
        lua_pushinteger(vm.state, Int64(self))
    }
    
    public func kind() -> Kind { return .number }
    
    public static func arg(_ vm: VirtualMachine, value: Value) -> String? {
        return Int64.arg(vm, value: value)
    }
    
}

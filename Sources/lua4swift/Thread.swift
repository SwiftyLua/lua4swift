import CLua

open class Thread: StoredValue, @unchecked Sendable {
    
    override open func kind() -> Kind { return .thread }
    
    override open class func arg(_ vm: VirtualMachine, value: Value) -> String? {
        if value.kind() != .thread { return "thread" }
        return nil
    }
    
}

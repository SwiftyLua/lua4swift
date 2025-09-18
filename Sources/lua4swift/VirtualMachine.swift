import Foundation
import CLua

internal let RegistryIndex = Int(-LUAI_MAXSTACK - 1000)
private let GlobalsTable = Int(LUA_RIDX_GLOBALS)

public enum MaybeFunction {
    case value(Function)
    case error(String)
}

public typealias ErrorHandler = (String) -> Void

public enum Kind {
    case string
    case number
    case boolean
    case function
    case table
    case userdata
    case lightUserdata
    case thread
    case `nil`
    case none

    internal func luaType() -> Int32 {
        switch self {
        case .string: return LUA_TSTRING
        case .number: return LUA_TNUMBER
        case .boolean: return LUA_TBOOLEAN
        case .function: return LUA_TFUNCTION
        case .table: return LUA_TTABLE
        case .userdata: return LUA_TUSERDATA
        case .lightUserdata: return LUA_TLIGHTUSERDATA
        case .thread: return LUA_TTHREAD
        case nil: return LUA_TNIL

        case .none:
            fallthrough
        default:
            return LUA_TNONE
        }
    }
}

open class VirtualMachine {

    public let state = luaL_newstate()

    open var errorHandler: ErrorHandler? = { print("error: \($0)") }

    public init(openLibs: Bool = true) {
        if openLibs { luaL_openlibs(state) }
    }

    deinit {
        lua_close(state)
    }

    public func preloadModules(_ modules: UnsafeMutablePointer<luaL_Reg>) {
        lua_getglobal(state, "package")
        lua_getfield(state, -1, "preload");

        var module = modules.pointee

        while let name = module.name, let function = module.func {
            lua_pushcclosure(state, function, 0)
            lua_setfield(state, -2, name)

            module = modules.advanced(by: 1).pointee
        }

        lua_settop(state, -(2)-1)
    }

    internal func kind(_ pos: Int) -> Kind {
        switch lua_type(state, Int32(pos)) {
        case LUA_TSTRING: return .string
        case LUA_TNUMBER: return .number
        case LUA_TBOOLEAN: return .boolean
        case LUA_TFUNCTION: return .function
        case LUA_TTABLE: return .table
        case LUA_TUSERDATA: return .userdata
        case LUA_TLIGHTUSERDATA: return .lightUserdata
        case LUA_TTHREAD: return .thread
        case LUA_TNIL: return .nil
        default: return .none
        }
    }

    // pops the value off the stack completely and returns it
    internal func popValue(_ pos: Int) -> Value? {
        moveToStackTop(pos)
        var v: Value?
        switch kind(-1) {
        case .string:
            var len: Int = 0
            let str = lua_tolstring(state, -1, &len)
            v = String(cString: str!)
        case .number:
            v = Number(self)
        case .boolean:
            v = lua_toboolean(state, -1) == 1 ? true : false
        case .function:
            v = Function(self)
        case .table:
            v = Table(self)
        case .userdata:
            v = Userdata(self)
        case .lightUserdata:
            v = LightUserdata(self)
        case .thread:
            v = Thread(self)
        case .nil:
            v = Nil()
        default: break
        }
        pop()
        return v
    }

    open var globals: Table {
        rawGet(tablePosition: RegistryIndex, index: GlobalsTable)
        return popValue(-1) as! Table
    }

    open var registry: Table {
        pushFromStack(RegistryIndex)
        return popValue(-1) as! Table
    }

    open func createFunction(_ body: URL) -> MaybeFunction {
        if luaL_loadfilex(state, body.path, nil) == LUA_OK {
            return .value(popValue(-1) as! Function)
        }
        else {
            return .error(popError())
        }
    }

    open func createFunction(_ body: String) -> MaybeFunction {
      if luaL_loadstring(state, body.cString(using: .utf8)) == LUA_OK {
            return .value(popValue(-1) as! Function)
        }
        else {
            return .error(popError())
        }
    }

    open func createTable(_ sequenceCapacity: Int = 0, keyCapacity: Int = 0) -> Table {
        lua_createtable(state, Int32(sequenceCapacity), Int32(keyCapacity))
        return popValue(-1) as! Table
    }

    internal func popError() -> String {
        let err = popValue(-1) as! String
        if let fn = errorHandler { fn(err) }
        return err
    }

    open func createUserdataMaybe<T: CustomTypeInstance>(_ o: T?) -> Userdata? {
        if let u = o {
            return createUserdata(u)
        }
        return nil
    }

    open func createUserdata<T: CustomTypeInstance>(_ o: T) -> Userdata {
        let userdata = lua_newuserdatauv(state, MemoryLayout<T>.size, 1) // this both pushes ptr onto stack and returns it

        let ptr = userdata!.bindMemory(to: T.self, capacity: 1)
        ptr.initialize(to: o) // creates a new legit reference to o

        luaL_setmetatable(state, T.luaTypeName().cString(using: .utf8)) // this requires ptr to be on the stack
        return popValue(-1) as! Userdata // this pops ptr off stack
    }

    public enum EvalResults {
        case values([Value])
        case error(String)
    }

    open func eval(_ url: URL, args: [Value] = []) -> EvalResults {
        let fn = createFunction(url)

        return eval(function: fn, args: args)
    }

    open func eval(_ str: String, args: [Value] = []) -> EvalResults {
        let fn = createFunction(str)

        return eval(function: fn, args: args)
    }

    private func eval(function fn: MaybeFunction, args: [Value])  -> EvalResults {
        switch fn {
        case let .value(f):
            let results = f.call(args)
            switch results {
            case let .values(vs):
                return .values(vs)
            case let .error(e):
                return .error(e)
            }
        case let .error(e):
            return .error(e)
        }
    }

    open func createFunction(_ typeCheckers: [TypeChecker], _ fn: @escaping SwiftFunction) -> Function {
        let f: @convention(block) (OpaquePointer) -> Int32 = { [weak self] _ in
            if self == nil { return 0 }
            let vm = self!

            // check types
            for i in 0 ..< vm.stackSize() {
                let typeChecker = typeCheckers[i]
                vm.pushFromStack(i+1)
                if let expectedType = typeChecker(vm, vm.popValue(-1)!) {
                    vm.argError(expectedType, at: i+1)
                }
            }

            // build args list
            let args = Arguments()
            for _ in 0 ..< vm.stackSize() {
                let arg = vm.popValue(1)!
                args.values.append(arg)
            }

            // call fn
            switch fn(args) {
            case .nothing:
                return 0
            case .value(let value):
                if let v = value {
                    v.push(vm)
                }
                else {
                    Nil().push(vm)
                }
                return 1
            case let .values(values):
                for value in values {
                    value.push(vm)
                }
                return Int32(values.count)
            case let .error(error):
                print("pushing error: \(error)")
                error.push(vm)
                lua_error(vm.state)
                return 0 // uhh, we don't actually get here
            }
        }
        let block: AnyObject = unsafeBitCast(f, to: AnyObject.self)
        let imp = imp_implementationWithBlock(block)

        let fp = unsafeBitCast(imp, to: lua_CFunction.self)
        lua_pushcclosure(state, fp, 0)
        return popValue(-1) as! Function
    }

    fileprivate func argError(_ expectedType: String, at argPosition: Int) {
        luaL_typeerror(state, Int32(argPosition), expectedType.cString(using: .utf8))
    }

    open func createCustomType<T>(_ setup: (CustomType<T>) -> Void) -> CustomType<T> {
        lua_createtable(state, 0, 0)
        let lib = CustomType<T>(self)
        pop()

        setup(lib)

        registry[T.luaTypeName()] = lib
        lib.becomeMetatableFor(lib)
        lib["__index"] = lib
        lib["__name"] = T.luaTypeName()

        let gc = lib.gc
        lib["__gc"] = createFunction([CustomType<T>.arg]) { args in
            let ud = args.userdata
            (ud.userdataPointer() as UnsafeMutablePointer<T>).deinitialize(count: 1)
            let o: T = ud.toCustomType()
            gc?(o)
            return .nothing
        }

        if let eq = lib.eq {
            lib["__eq"] = createFunction([CustomType<T>.arg, CustomType<T>.arg]) { args in
                let a: T = args.customType()
                let b: T = args.customType()
                return .value(eq(a, b))
            }
        }
        return lib
    }

    // stack

    internal func moveToStackTop(_ position: Int) {
        var position = position
        if position == -1 || position == stackSize() { return }
        position = absolutePosition(position)
        pushFromStack(position)
        remove(position)
    }

    internal func ref(_ position: Int) -> Int { return Int(luaL_ref(state, Int32(position))) }
    internal func unref(_ table: Int, _ position: Int) { luaL_unref(state, Int32(table), Int32(position)) }
    internal func absolutePosition(_ position: Int) -> Int { return Int(lua_absindex(state, Int32(position))) }
    internal func rawGet(tablePosition: Int, index: Int) { lua_rawgeti(state, Int32(tablePosition), lua_Integer(index)) }

    internal func pushFromStack(_ position: Int) {
        lua_pushvalue(state, Int32(position))
    }

    internal func pop(_ n: Int = 1) {
        lua_settop(state, -Int32(n)-1)
    }

    internal func rotate(_ position: Int, n: Int) {
        lua_rotate(state, Int32(position), Int32(n))
    }

    internal func remove(_ position: Int) {
        rotate(position, n: -1)
        pop(1)
    }

    internal func stackSize() -> Int {
        return Int(lua_gettop(state))
    }

}

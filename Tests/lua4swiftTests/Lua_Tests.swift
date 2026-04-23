import Foundation
import Testing

@testable import lua4swift

@Suite
struct Lua_Tests {

  @Test func fundamentals() {
    let vm = VirtualMachine()
    let table = vm.createTable()
    table[3] = "foo"
    #expect(table[3] is String)
    #expect(table[3] as! String == "foo")
  }

  @Test func stringX() {
    let vm = VirtualMachine()

    let stringxLib = vm.createTable()

    stringxLib["split"] = vm.createFunction([String.arg, String.arg]) { args in
      let (subject, separator) = (args.string, args.string)
      let fragments = subject.components(separatedBy: separator)

      let results = vm.createTable()
      for (i, fragment) in fragments.enumerated() {
        results[i+1] = fragment
      }
      return .value(results)
    }

    vm.globals["stringx"] = stringxLib

    switch vm.eval("return stringx.split('hello world', ' ')", args: []) {
      case let .values(values):
        #expect(values.count == 1)
        #expect(values[0] is Table)
        let array: [String] = (values[0] as! Table).asSequence()
        #expect(array == ["hello", "world"])
      case let .error(e):
        Issue.record("Lua eval error: \(e)")
    }
  }

  @Test func customType() {

    class Note: CustomTypeInstance, @unchecked Sendable {
      var name = ""
      static func luaTypeName() -> String {
        return "note"
      }
    }

    let vm = VirtualMachine()

    let noteLib: CustomType<Note> = vm.createCustomType {
      type in
      type["setName"] = type.createMethod([String.arg]) {
        note, args in
        note.name = args.string
        return .nothing
      }
      type["getName"] = type.createMethod([]) {
        note, args in
        return .value(note.name)
      }
    }

    noteLib["new"] = vm.createFunction([String.arg]) {
      args in
      let note = Note()
      note.name = args.string
      let data = vm.createUserdata(note)
      return .value(data)
    }

    // setup the note class
    vm.globals["note"] = noteLib

    _ = vm.eval("myNote = note.new('a custom note')")
    #expect(vm.globals["myNote"] is Userdata)

    // extract the note
    // and see if the name is the same

    let myNote: Note = (vm.globals["myNote"] as! Userdata).toCustomType()
    #expect(myNote.name == "a custom note")

    // This is just to highlight changes in Swift
    // will get reflected in Lua as well

    myNote.name = "now from Swift Testing"
    _ = vm.eval("print(myNote:getName())")

    // further checks to change name in Lua
    // and see change reflected in the Swift object

    _ = vm.eval("myNote:setName('even')")
    #expect(myNote.name == "even")

    _ = vm.eval("myNote:setName('odd')")
    #expect(myNote.name == "odd")

  }

}

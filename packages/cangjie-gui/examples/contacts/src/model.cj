/*
 * 通讯录模型：联系人列表 + 搜索过滤 + 增改删，以及两个对话框（表单、删除确认）的状态。
 *
 * 表格展示的是“过滤后的可见列表”，`selected` 是可见列表中的行索引。搜索变化时观察器把选择归零，
 * 避免选中项指向被过滤掉的行。表单不直接改联系人，而是编辑一组草稿 State，保存时整体写回，
 * 取消即丢弃——单一数据源、无需回滚。
 */
package cui_contacts

import std.collection.ArrayList
import cui.{State, StateObservation}

class ContactsModel {
    let contacts = State<Array<Contact>>(seedContacts())
    let selected = State<Int64>(-1)
    let query = State<String>("")
    let formOpen = State<Bool>(false)
    let confirmDelete = State<Bool>(false)
    let draftName = State<String>("")
    let draftCompany = State<String>("")
    let draftRole = State<String>("")
    let draftEmail = State<String>("")
    private var editingId: Int64 = -1
    private var nextId: Int64 = 100
    private let queryObservation: StateObservation<String>

    init() {
        // 过滤条件变化时清空选择：否则指向旧可见列表的行索引会落在另一位（或已被过滤掉的）
        // 联系人上。先把字段读入局部变量，避免闭包在全部成员初始化完成前捕获 `this`。
        let selectionState = this.selected
        this.queryObservation = this.query.observe({_, _ => selectionState.value = -1})
    }

    /** 匹配当前搜索词的联系人，任一字段命中即算匹配。 */
    func visible(): Array<Contact> {
        let q = query.value.toAsciiLower()
        if (q.isEmpty()) {
            return contacts.value
        }
        let result = ArrayList<Contact>()
        for (contact in contacts.value) {
            if (matchesQuery(contact, q)) {
                result.add(contact)
            }
        }
        result.toArray()
    }

    /** 可见联系人转成的表格单元格数据（姓名、公司、职务、邮箱）。 */
    func rows(): Array<Array<String>> {
        let list = visible()
        Array<Array<String>>(list.size, {i => [list[i].name, list[i].company, list[i].role, list[i].email]})
    }

    func selectedContact(): ?Contact {
        let list = visible()
        let index = selected.value
        if (index >= 0 && index < list.size) {
            Some(list[index])
        } else {
            None
        }
    }

    func startAdd(): Unit {
        editingId = -1
        setDraft("", "", "", "")
        formOpen.value = true
    }

    func startEdit(): Unit {
        match (selectedContact()) {
            case Some(contact) =>
                editingId = contact.id
                setDraft(contact.name, contact.company, contact.role, contact.email)
                formOpen.value = true
            case None => ()
        }
    }

    /** 姓名为必填项；未填写时表单的保存按钮保持禁用。 */
    func canSave(): Bool {
        !draftName.value.isEmpty()
    }

    func saveForm(): Unit {
        if (!canSave()) {
            return
        }
        if (editingId < 0) {
            nextId += 1
            appendContact(Contact(nextId, draftName.value, draftCompany.value, draftRole.value, draftEmail.value))
        } else {
            replaceContact(Contact(editingId, draftName.value, draftCompany.value, draftRole.value, draftEmail.value))
        }
        formOpen.value = false
    }

    func requestDelete(): Unit {
        match (selectedContact()) {
            case Some(_) => confirmDelete.value = true
            case None => ()
        }
    }

    func deleteSelected(): Unit {
        match (selectedContact()) {
            case Some(contact) =>
                removeContact(contact.id)
                selected.value = -1
            case None => ()
        }
        confirmDelete.value = false
    }

    func editingTitle(): String {
        if (editingId < 0) {
            "新增联系人"
        } else {
            "编辑联系人"
        }
    }

    private func setDraft(name: String, company: String, role: String, email: String): Unit {
        draftName.value = name
        draftCompany.value = company
        draftRole.value = role
        draftEmail.value = email
    }

    private func appendContact(contact: Contact): Unit {
        let current = contacts.value
        contacts.value = Array<Contact>(current.size + 1, {i => if (i < current.size) {
            current[i]
        } else {
            contact
        }})
        selected.value = -1
    }

    private func replaceContact(updated: Contact): Unit {
        let current = contacts.value
        contacts.value = Array<Contact>(current.size, {i => if (current[i].id == updated.id) {
            updated
        } else {
            current[i]
        }})
    }

    private func removeContact(id: Int64): Unit {
        let remaining = ArrayList<Contact>()
        for (contact in contacts.value) {
            if (contact.id != id) {
                remaining.add(contact)
            }
        }
        contacts.value = remaining.toArray()
    }
}

func matchesQuery(contact: Contact, lowerQuery: String): Bool {
    contact.name.toAsciiLower().contains(lowerQuery) || contact.company.toAsciiLower().contains(lowerQuery) ||
        contact.role.toAsciiLower().contains(lowerQuery) || contact.email.toAsciiLower().contains(lowerQuery)
}

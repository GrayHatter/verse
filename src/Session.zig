id: Id,
store: *Store = undefined,
map: std.StringHashMapUnmanaged([]const u8) = .empty,

const Session = @This();

/// Base64 sha256
pub const Id = [40]u8;

/// Session Store/Manager `Store.VTable` retains the session data across
/// requests.
///
/// See Also:
///   `Store.Memory`
///   `Store.FileSystem` TODO
pub const Store = struct {
    // TODO managed?
    alloc: Allocator,
    vtable: *const VTable = .none,
    sign: enum { signed, unsigned } = .unsigned,

    pub const VTable = struct {
        init: ?initFn,
        /// Called after the end of the request, before `*Session` is cleaned
        /// up. All live session state may be destroyed, so implementations
        /// should duplicate data they need to retain.
        raze: ?razeFn,
        save: ?saveFn,
        load: ?loadFn,
        /// deinit must not fail
        destroy: destroyFn = nopDestroy,

        pub const none: *const VTable = &.{
            .init = null,
            .raze = null,
            .save = null,
            .load = null,
        };

        pub const InitError = error{OutOfMemory};
        pub const SaveError = error{ OutOfMemory, BackingFault };

        pub const initFn = *const fn (*Store) InitError!void;
        pub const razeFn = *const fn (*Store) void;
        pub const saveFn = *const fn (*Store, *const Session) SaveError!void;
        pub const loadFn = *const fn (*Store, Id) ?Session;
        pub const destroyFn = *const fn (*Store, *const Session) void;

        pub fn nopDestroy(_: *Store, _: *const Session) void {}
    };

    pub const Memory = struct {
        mstore: Store,
        alloc: Allocator,
        map: std.AutoHashMapUnmanaged(Id, Session),

        pub const vtable: Store.VTable = .{
            .init = &storeInit,
            .raze = &storeRaze,
            .save = &Memory.save,
            .load = &Memory.load,
            .destroy = &Memory.destroy,
        };

        pub fn init(a: Allocator) Memory {
            return .{
                .mstore = .{
                    .alloc = a,
                    .vtable = &vtable,
                },
                .alloc = a,
                .map = .empty,
            };
        }

        pub fn store(mem: *Memory) *Store {
            return &mem.mstore;
        }

        pub fn storeInit(s: *Store) !void {
            const mem: *Memory = @fieldParentPtr("mstore", s);
            mem.map.deinit(s.alloc);
        }

        pub fn storeRaze(s: *Store) void {
            const mem: *Memory = @fieldParentPtr("mstore", s);
            mem.map.deinit(mem.alloc);
        }

        pub fn save(s: *Store, sess: *const Session) VTable.SaveError!void {
            const mem: *Memory = @fieldParentPtr("mstore", s);
            return mem.map.put(mem.alloc, sess.id, sess.*);
        }

        /// Asserts found session.id == id
        pub fn load(s: *Store, id: Id) ?Session {
            const mem: *Memory = @fieldParentPtr("mstore", s);
            var sess = mem.map.get(id) orelse return null;
            std.debug.assert(std.mem.eql(u8, &sess.id, &id));
            sess.store = s;
            return sess;
        }

        pub fn destroy(s: *Store, sess: *const Session) void {
            const mem: *Memory = @fieldParentPtr("mstore", s);
            _ = mem.map.remove(sess.id);
        }

        test Memory {
            _ = std.testing.refAllDecls(Memory);
            const a = std.testing.allocator;
            const id: Id = @splat('3');
            const noid: Id = @splat('0');

            var mem: Memory = .init(a);

            const lstore: *Store = mem.store();
            defer lstore.raze();
            var found = lstore.find(noid);
            try std.testing.expectEqual(null, found);
            found = lstore.find(id);
            try std.testing.expectEqual(null, found);

            const session: Session = .{
                .id = id,
                .store = lstore,
                .map = .empty,
            };

            try lstore.commit(&session);
            try std.testing.expectEqual(null, found);
            found = lstore.find(noid);
            try std.testing.expectEqual(null, found);
            found = lstore.find(id);
            try std.testing.expectEqualDeep(Session{
                .id = id,
                .store = lstore,
                .map = .empty,
            }, found);
        }
    };

    pub const FileSystem = struct {
        // TODO
    };

    pub fn find(s: *Store, id: Id) !?Session {
        const loadF: VTable.loadFn = s.vtable.load orelse return error.Unavailable;
        return loadF(s, id);
    }

    pub fn findOrNew(s: *Store, id: Id) !Session {
        return s.find(id) catch (try s.new(id)) orelse try s.new(id);
    }

    pub fn new(s: *Store, id: Id) !Session {
        const sess: Session = .{
            .id = id,
            .store = s,
            .map = .empty,
        };
        return sess;
    }

    pub const CommitError = error{
        Unavailable,
    };

    pub fn commit(s: *Store, sess: *const Session) !void {
        const saveF: VTable.saveFn = s.vtable.save orelse return error.Unavailable;
        try saveF(s, sess);
    }

    fn makeId(_: *Store, io: std.Io) Id {
        var id: Id = undefined;
        io.random(&id);
        return id;
    }

    pub fn destroy(s: *Store, sess: *const Session) void {
        const destroyF: VTable.destroyFn = s.vtable.destroy;
        destroyF(s, sess);
    }

    pub fn raze(s: *Store) void {
        const razeF: VTable.razeFn = s.vtable.raze orelse return;
        razeF(s);
    }

    test Store {
        _ = std.testing.refAllDecls(Store);
    }
};

pub fn init(id: Id, s: *Store) Session {
    return .{
        .id = id,
        .store = s,
        .map = .empty,
    };
}

pub fn raze(sess: *Session) void {
    sess.map.deinit(sess.store.alloc);
    sess.store.destroy(sess);
}

pub fn get(s: *const Session, comptime el: @EnumLiteral()) ?[]const u8 {
    const target = @tagName(el);
    return s.map.get(target);
}

pub fn put(s: *Session, comptime el: @EnumLiteral(), thing: []const u8) error{OutOfMemory}!void {
    const target = @tagName(el);
    try s.map.put(s.store.alloc, target, thing);
}

pub fn save(sess: *const Session) !void {
    try sess.store.commit(sess);
}

pub fn load(sess: *const Session) ?Session {
    return sess.store.find(sess.id) catch null;
}

/// Removes all k/v pair, but retains the session `Id`
pub fn clear(sess: *Session) void {
    sess.map.deinit(sess.store.alloc);
}

test Session {
    _ = std.testing.refAllDecls(Session);

    const a = std.testing.allocator;
    const id: Id = @splat('3');
    var mem: Store.Memory = .init(a);
    const lstore: *Store = mem.store();
    defer lstore.raze();

    var session: Session = .{
        .id = id,
        .store = lstore,
    };

    try lstore.commit(&session);
    var found = lstore.find(id) catch unreachable orelse return error.SessionNotFound;
    defer found.raze();
    try std.testing.expectEqualDeep(Session{
        .id = id,
        .store = lstore,
    }, found);

    try found.put(.testing, "this is that string");
    try std.testing.expectEqual(found.map.count(), 1);
    const str = found.get(.testing) orelse return error.NotFound;
    try std.testing.expectEqualStrings("this is that string", str);
    if (found.get(.testing_fake)) |_| return error.BadFound;
}

const std = @import("std");
const Allocator = std.mem.Allocator;

// Span stores indices of where given token or node starts and ends.
pub const Span = struct {
    start: usize,
    end: usize,

    const Self = @This();

    pub fn len(span: Self) usize {
        return span.end - span.start;
    }
};

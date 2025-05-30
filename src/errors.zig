/// Errors that indicate something is wrong with the host system verse is
/// running ontop of.
pub const ServerError = error{
    OutOfMemory,
    NoSpaceLeft,
    NotImplemented,
    Unknown,
    ServerFault,
};

/// Errors resulting from data from the client preventing verse, or an endpoint
/// from returning a valid response.
pub const ClientError = error{
    Abusive,
    BadData,
    DataMissing,
    InvalidURI,
    Unauthenticated,
    Unrouteable,
};

/// Networking or other IO errors.
pub const NetworkError = error{
    /// Common and usually banal error when the client disconnects before the
    /// full response is delivered.
    BrokenPipe,
    IOWriteFailure,
    NoSpaceLeft,
};

pub const Error = ServerError || ClientError || NetworkError;

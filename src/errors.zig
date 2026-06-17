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
    Abuse,
    /// Returns 422
    DataInvalid,
    /// Returns 400
    DataMissing,
    InvalidURI,
    /// Returns 401
    Unauthenticated,
    /// Returns 403
    Unauthorized,
    /// Returns 404
    NotFound,
};

/// Networking or other IO errors.
pub const NetworkError = error{
    /// Common and usually banal error when the client disconnects before the
    /// full response is delivered.
    WriteFailed,
    NoSpaceLeft,
};

pub const RoutingError = error{
    Unrouteable,
    MethodNotAllowed,
    NotFound,
};

pub const Error = ServerError || ClientError || NetworkError;

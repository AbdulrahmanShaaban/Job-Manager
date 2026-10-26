export type ErrorCode =
  | "BAD_REQUEST"
  | "VALIDATION_ERROR"
  | "UNAUTHORIZED"
  | "FORBIDDEN"
  | "NOT_FOUND"
  | "CONFLICT"
  | "RATE_LIMITED"
  | "AI_UNAVAILABLE"
  | "AI_QUOTA_EXHAUSTED"
  | "AI_NOT_ALLOWED"
  | "PAYLOAD_TOO_LARGE"
  | "INTERNAL_ERROR";

export class ApiError extends Error {
  readonly status: number;
  readonly code: ErrorCode;
  readonly details?: unknown;

  constructor(status: number, code: ErrorCode, message: string, details?: unknown) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
    this.details = details;
  }

  static badRequest(message = "Invalid request") {
    return new ApiError(400, "BAD_REQUEST", message);
  }

  static unauthorized(message = "Authentication required") {
    return new ApiError(401, "UNAUTHORIZED", message);
  }

  static forbidden(message = "You do not have permission to do that") {
    return new ApiError(403, "FORBIDDEN", message);
  }

  static notFound(message = "Record not found") {
    return new ApiError(404, "NOT_FOUND", message);
  }

  static conflict(message = "Record was changed by someone else", details?: unknown) {
    return new ApiError(409, "CONFLICT", message, details);
  }

  static validation(details: unknown, message = "Some fields are invalid") {
    return new ApiError(422, "VALIDATION_ERROR", message, details);
  }
}

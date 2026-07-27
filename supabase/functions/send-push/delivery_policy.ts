export const MAX_PUSH_DELIVERY_ATTEMPTS = 2;

export type PushFailureClass = "expired" | "retryable" | "permanent";

export type PushDeliveryOutcome<T> =
  | {
    success: true;
    value: T;
    attempts: number;
    statusCode: number | null;
  }
  | {
    success: false;
    error: unknown;
    attempts: number;
    statusCode: number | null;
    failureClass: PushFailureClass;
  };

export function readPushStatusCode(error: unknown): number | null {
  if (typeof error !== "object" || error === null) return null;
  const statusCode = (error as { statusCode?: unknown }).statusCode;
  return typeof statusCode === "number" && Number.isFinite(statusCode)
    ? statusCode
    : null;
}

export function classifyPushFailure(
  statusCode: number | null,
): PushFailureClass {
  if (statusCode === 404 || statusCode === 410) return "expired";

  if (
    statusCode === null ||
    statusCode === 408 ||
    statusCode === 425 ||
    statusCode === 429 ||
    statusCode >= 500
  ) {
    return "retryable";
  }

  return "permanent";
}

export function pushRetryDelayMs(completedAttempts: number): number {
  const normalizedAttempts = Math.max(1, Math.floor(completedAttempts));
  return Math.min(250 * 2 ** (normalizedAttempts - 1), 2_000);
}

export async function executePushDelivery<T>(
  operation: () => Promise<T>,
  options: {
    maxAttempts?: number;
    sleep?: (milliseconds: number) => Promise<void>;
  } = {},
): Promise<PushDeliveryOutcome<T>> {
  const maxAttempts = Math.max(
    1,
    Math.floor(options.maxAttempts ?? MAX_PUSH_DELIVERY_ATTEMPTS),
  );
  const sleep = options.sleep ?? ((milliseconds: number) =>
    new Promise<void>((resolve) => setTimeout(resolve, milliseconds)));

  let attempts = 0;

  while (attempts < maxAttempts) {
    attempts += 1;
    try {
      const value = await operation();
      const statusCode = typeof value === "object" && value !== null
        ? readPushStatusCode(value)
        : null;
      return { success: true, value, attempts, statusCode };
    } catch (error) {
      const statusCode = readPushStatusCode(error);
      const failureClass = classifyPushFailure(statusCode);

      if (failureClass === "retryable" && attempts < maxAttempts) {
        await sleep(pushRetryDelayMs(attempts));
        continue;
      }

      return {
        success: false,
        error,
        attempts,
        statusCode,
        failureClass,
      };
    }
  }

  throw new Error("push delivery retry loop ended unexpectedly");
}

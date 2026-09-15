export const MAX_PUSH_DELIVERY_ATTEMPTS = 2;

/// Combien de temps le service de notification garde un message pour un
/// appareil injoignable.
///
/// Passé ce délai, le message est jeté et rien ne le rattrape : le destinataire
/// ne saura jamais qu'on a cherché à le joindre. Notre journal, lui, continue
/// d'afficher un envoi réussi, parce que le service l'avait bien accepté.
///
/// Une heure était trop court. Un téléphone éteint, en avion, dans le métro ou
/// simplement hors réseau au mauvais moment perdait définitivement l'ouverture
/// des disponibilités — constaté le 15 septembre 2026 sur un joueur qui avait
/// reçu sans problème celle de la semaine précédente.
///
/// Vingt-quatre heures couvrent une nuit et une journée de travail. Aucune de
/// nos notifications n'est urgente à la minute : la plus serrée prévient d'un
/// match le lendemain, et les relances de disponibilité se répètent à J-3 et
/// J-1. Au-delà d'une journée, un message deviendrait trompeur plutôt
/// qu'utile.
export const PUSH_DELIVERY_TTL_SECONDS = 86_400;

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

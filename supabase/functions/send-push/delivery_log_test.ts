import {
  optionalMatchId,
  TARGETED_DELIVERY_LOG_KINDS,
  targetedDeliveryLogKind,
} from "./delivery_log.ts";

function assertEquals<T>(actual: T, expected: T, message?: string): void {
  if (!Object.is(actual, expected)) {
    throw new Error(
      message ?? `Expected ${String(expected)}, received ${String(actual)}`,
    );
  }
}

Deno.test("garde le type transmis par la base pour les envois ciblés", () => {
  for (
    const kind of [
      "convocation_promoted",
      "convocation_demoted",
      "composition_published",
      "motm_result_general",
      "motm_result_winner",
      "badge_unlocked",
    ]
  ) {
    assertEquals(targetedDeliveryLogKind(kind), kind, kind);
  }
  assertEquals(TARGETED_DELIVERY_LOG_KINDS.size, 6);
});

Deno.test("un type absent ou inconnu est journalisé comme custom", () => {
  assertEquals(targetedDeliveryLogKind(undefined), "custom");
  assertEquals(targetedDeliveryLogKind(null), "custom");
  assertEquals(targetedDeliveryLogKind(""), "custom");
  assertEquals(targetedDeliveryLogKind(42), "custom");
  // Un type valide pour d'autres envois ne passe pas par ce chemin.
  assertEquals(targetedDeliveryLogKind("availability_open"), "custom");
  assertEquals(
    targetedDeliveryLogKind("drop table push_delivery_log"),
    "custom",
  );
});

Deno.test("le match n'est gardé que s'il a la forme d'un identifiant", () => {
  assertEquals(
    optionalMatchId("5E51FFE5-01BE-4C42-ABE9-C39EC9BC6A47"),
    "5e51ffe5-01be-4c42-abe9-c39ec9bc6a47",
  );
  assertEquals(
    optionalMatchId(" 5e51ffe5-01be-4c42-abe9-c39ec9bc6a47 "),
    "5e51ffe5-01be-4c42-abe9-c39ec9bc6a47",
  );
  assertEquals(optionalMatchId(undefined), null);
  assertEquals(optionalMatchId(null), null);
  assertEquals(optionalMatchId(""), null);
  assertEquals(optionalMatchId("matches/5e51ffe5"), null);
  assertEquals(optionalMatchId(123), null);
});

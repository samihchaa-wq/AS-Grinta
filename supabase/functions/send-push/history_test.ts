import {
  historyKind,
  historyRecipients,
  payloadForProfile,
  payloadText,
  profileIdList,
  shouldRecordHistory,
  unreadCounts,
} from "./history.ts";

function assertEquals<T>(actual: T, expected: T, message?: string): void {
  if (!Object.is(actual, expected)) {
    throw new Error(
      message ?? `Expected ${String(expected)}, received ${String(actual)}`,
    );
  }
}

const ALICE = "c7000000-0000-0000-0000-000000000002";
const BRUNO = "c7000000-0000-0000-0000-000000000003";

Deno.test("seul un refus explicite empêche l'enregistrement", () => {
  assertEquals(shouldRecordHistory({}), true);
  assertEquals(shouldRecordHistory({ record_history: true }), true);
  assertEquals(shouldRecordHistory({ record_history: "false" }), true);
  assertEquals(shouldRecordHistory({ record_history: false }), false);
});

Deno.test("un type mal formé est rangé comme custom", () => {
  assertEquals(historyKind("availability_open"), "availability_open");
  assertEquals(historyKind("live_goal_us"), "live_goal_us");
  assertEquals(historyKind(undefined), "custom");
  assertEquals(historyKind(""), "custom");
  assertEquals(historyKind("Drop Table"), "custom");
  assertEquals(historyKind("a".repeat(65)), "custom");
});

Deno.test("les identifiants invalides ou répétés sont écartés", () => {
  const ids = profileIdList([ALICE, ALICE.toUpperCase(), "pas-un-uuid", 42, BRUNO]);
  assertEquals(ids.length, 2);
  assertEquals(ids[0], ALICE);
  assertEquals(ids[1], BRUNO);
  assertEquals(profileIdList(null).length, 0);
});

Deno.test("les destinataires viennent de la base, sinon des téléphones", () => {
  const subscriptions = [{ profile_id: BRUNO }, { profile_id: BRUNO }];
  const fromDatabase = historyRecipients(
    { recipient_profile_ids: [ALICE, BRUNO] },
    subscriptions,
  );
  assertEquals(fromDatabase.join(","), `${ALICE},${BRUNO}`);

  // Liste vide fournie par la base : personne, même si un téléphone existe.
  assertEquals(
    historyRecipients({ recipient_profile_ids: [] }, subscriptions).length,
    0,
  );

  // Ancienne base sans la liste : profils des téléphones abonnés.
  assertEquals(historyRecipients({}, subscriptions).join(","), BRUNO);
});

Deno.test("seuls les nombres entiers positifs sont gardés", () => {
  const counts = unreadCounts({ [ALICE]: 3, [BRUNO]: -1, other: "2", x: 1.5 });
  assertEquals(counts.size, 1);
  assertEquals(counts.get(ALICE), 3);
  assertEquals(unreadCounts(null).size, 0);
  assertEquals(unreadCounts([1, 2]).size, 0);
});

Deno.test("chaque téléphone reçoit le nombre de non-lues de son propriétaire", () => {
  const payload = { title: "Disponibilité", body: "Es-tu dispo ?", url: "matches", tag: "t" };
  const unread = new Map([[ALICE, 4], [BRUNO, 0]]);

  assertEquals(JSON.parse(payloadForProfile(payload, ALICE, unread)).app_badge, 4);
  assertEquals(
    JSON.parse(payloadForProfile(payload, BRUNO.toUpperCase(), unread)).app_badge,
    0,
  );

  // Nombre inconnu : le contenu part tel quel, sans app_badge.
  const unknown = JSON.parse(payloadForProfile(payload, undefined, unread));
  assertEquals("app_badge" in unknown, false);
  assertEquals(unknown.title, "Disponibilité");
  assertEquals(unknown.badge, undefined);
});

Deno.test("un champ absent devient une chaîne vide", () => {
  assertEquals(payloadText("Titre"), "Titre");
  assertEquals(payloadText(undefined), "");
  assertEquals(payloadText(12), "");
});

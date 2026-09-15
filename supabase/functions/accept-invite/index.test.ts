import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";

import {
  classifyTokenInvite,
  tokenInviteResponse,
  type TokenInviteRow,
} from "./invite_result.ts";

function makeInvite(overrides: Partial<TokenInviteRow> = {}): TokenInviteRow {
  return {
    id: "invite-123",
    band_id: "band-456",
    email: "invitee@example.com",
    status: "pending",
    expires_at: "2030-01-01T00:00:00.000Z",
    bands: { name: "The Roadies" },
    ...overrides,
  };
}

Deno.test("classifyTokenInvite returns not_found when the token does not exist", () => {
  assertEquals(
    classifyTokenInvite(
      null,
      "invitee@example.com",
      new Date("2029-01-01T00:00:00.000Z"),
    ),
    { kind: "not_found" },
  );
});

Deno.test("classifyTokenInvite returns email_mismatch for a different email", () => {
  assertEquals(
    classifyTokenInvite(
      makeInvite({ email: "other@example.com" }),
      "invitee@example.com",
      new Date("2029-01-01T00:00:00.000Z"),
    ),
    { kind: "email_mismatch" },
  );
});

Deno.test("classifyTokenInvite returns consumed for accepted invites", () => {
  assertEquals(
    classifyTokenInvite(
      makeInvite({ status: "accepted" }),
      "invitee@example.com",
      new Date("2029-01-01T00:00:00.000Z"),
    ),
    { kind: "unavailable", reason: "consumed" },
  );
});

Deno.test("classifyTokenInvite returns ineligible for non-pending and non-sent invites", () => {
  assertEquals(
    classifyTokenInvite(
      makeInvite({ status: "declined" }),
      "invitee@example.com",
      new Date("2029-01-01T00:00:00.000Z"),
    ),
    { kind: "unavailable", reason: "ineligible" },
  );
});

Deno.test("classifyTokenInvite returns expired for elapsed invites", () => {
  assertEquals(
    classifyTokenInvite(
      makeInvite({ expires_at: "2020-01-01T00:00:00.000Z" }),
      "invitee@example.com",
      new Date("2029-01-01T00:00:00.000Z"),
    ),
    { kind: "unavailable", reason: "expired" },
  );
});

Deno.test("classifyTokenInvite returns eligible for a matching pending invite", () => {
  const invite = makeInvite();
  assertEquals(
    classifyTokenInvite(
      invite,
      "INVITEE@example.com",
      new Date("2029-01-01T00:00:00.000Z"),
    ),
    { kind: "eligible", invite },
  );
});

Deno.test("tokenInviteResponse returns success for an eligible invite", () => {
  const result = tokenInviteResponse({
    kind: "eligible",
    invite: makeInvite(),
  });
  assertEquals(result.status, 200);
  assertEquals(result.body, {
    success: true,
    accepted_count: 1,
    band_names: ["The Roadies"],
    accepted_band_id: "band-456",
    accepted_band_ids: ["band-456"],
  });
});

Deno.test("tokenInviteResponse returns accept_failed for an eligible invite with RPC failure", () => {
  const result = tokenInviteResponse(
    { kind: "eligible", invite: makeInvite() },
    { rpcFailed: true },
  );
  assertEquals(result.status, 502);
  assertEquals(result.body, {
    error: "We couldn't finish accepting your invite. Please try again.",
    code: "accept_failed",
  });
});

Deno.test("tokenInviteResponse returns email_mismatch for the mismatch bucket", () => {
  const result = tokenInviteResponse({ kind: "email_mismatch" });
  assertEquals(result.status, 403);
  assertEquals(result.body, {
    error: "This invite was sent to a different email.",
    code: "email_mismatch",
  });
});

for (
  const classification of [
    { kind: "not_found" } as const,
    { kind: "unavailable", reason: "consumed" } as const,
    { kind: "unavailable", reason: "ineligible" } as const,
    { kind: "unavailable", reason: "expired" } as const,
  ]
) {
  Deno.test(`tokenInviteResponse returns invite_unavailable for ${classification.kind}${"reason" in classification ? `:${classification.reason}` : ""}`, () => {
    const result = tokenInviteResponse(classification);
    assertEquals(result.status, 409);
    assertEquals(result.body, {
      error: "This invite is no longer available.",
      code: "invite_unavailable",
    });
  });
}

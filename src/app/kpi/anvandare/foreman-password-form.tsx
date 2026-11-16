"use client";

import { useActionState } from "react";

export type PasswordResult = { success: boolean; message: string } | null;
type PasswordAction = (previous: PasswordResult, form: FormData) => Promise<PasswordResult>;

export function ForemanPasswordForm({ accountId, action }: { accountId: string; action: PasswordAction }) {
  const [result, submit, pending] = useActionState(action, null);

  return <form action={submit} style={{ display: "grid", gap: 8, justifyItems: "start" }}>
    <input type="hidden" name="id" value={accountId} />
    <label>Nytt lösenord (minst 12 tecken)
      <input type="password" name="password" minLength={12} required autoComplete="new-password" />
    </label>
    <button type="submit" className="primary" disabled={pending}>
      {pending ? "Sparar lösenord…" : "Spara nytt lösenord"}
    </button>
    {!pending && result && <p role={result.success ? "status" : "alert"}>{result.message}</p>}
  </form>;
}

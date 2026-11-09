"use client";

import { useFormStatus } from "react-dom";

export function LoginSubmit() {
  const { pending } = useFormStatus();

  return <button className="primary" type="submit" disabled={pending} aria-live="polite">
    {pending ? "Öppnar Humla…" : "Öppna Humla"}
  </button>;
}

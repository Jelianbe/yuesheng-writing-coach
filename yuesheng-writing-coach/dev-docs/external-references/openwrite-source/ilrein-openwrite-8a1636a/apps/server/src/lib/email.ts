import { env } from "cloudflare:workers"

/**
 * Transactional email sending via the Cloudflare Email Service binding.
 * The sender domain must be onboarded to Email Sending (iliareingold.com is).
 */

const FROM = { email: "noreply@iliareingold.com", name: "OpenWrite" }

interface ActionEmail {
  actionLabel: string
  actionUrl: string
  body: string
  subject: string
  to: string
}

function renderHtml({ body, actionUrl, actionLabel }: ActionEmail): string {
  return `<!doctype html>
<html lang="en">
  <body style="margin:0;padding:32px 16px;background:#f6f6f4;font-family:Georgia,'Times New Roman',serif;color:#1a1a1a;">
    <div style="max-width:480px;margin:0 auto;background:#ffffff;border:1px solid #e5e5e0;border-radius:8px;padding:32px;">
      <h1 style="margin:0 0 16px;font-size:20px;">OpenWrite</h1>
      <p style="margin:0 0 24px;font-size:15px;line-height:1.6;">${body}</p>
      <a href="${actionUrl}" style="display:inline-block;background:#1a1a1a;color:#ffffff;text-decoration:none;padding:10px 20px;border-radius:6px;font-size:14px;">${actionLabel}</a>
      <p style="margin:24px 0 0;font-size:12px;color:#8a8a85;line-height:1.6;">If the button doesn't work, copy this link into your browser:<br>${actionUrl}</p>
      <p style="margin:16px 0 0;font-size:12px;color:#8a8a85;">If you didn't request this, you can safely ignore this email.</p>
    </div>
  </body>
</html>`
}

function renderText({ body, actionUrl }: ActionEmail): string {
  return `OpenWrite

${body}

${actionUrl}

If you didn't request this, you can safely ignore this email.`
}

export async function sendActionEmail(email: ActionEmail): Promise<void> {
  await env.EMAIL.send({
    to: email.to,
    from: FROM,
    subject: email.subject,
    html: renderHtml(email),
    text: renderText(email),
  })
}

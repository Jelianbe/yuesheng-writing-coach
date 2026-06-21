import { betterAuth } from "better-auth"
import { drizzleAdapter } from "better-auth/adapters/drizzle"
import { organization } from "better-auth/plugins"
import { db } from "../db"
import {
  account,
  invitation,
  member,
  organization as organizationTable,
  session,
  team,
  teamMember,
  user,
  verification,
} from "../db/schema"
import { sendActionEmail } from "./email"

interface AuthEnv {
  BETTER_AUTH_SECRET: string
  BETTER_AUTH_URL: string
  CORS_ORIGIN: string
}

function buildAuthInstance(env: AuthEnv) {
  return betterAuth({
    database: drizzleAdapter(db, {
      provider: "sqlite",
      schema: {
        user,
        session,
        account,
        verification,
        organization: organizationTable,
        member,
        invitation,
        team,
        teamMember,
      },
    }),
    databaseHooks: {
      user: {
        create: {
          after: async (createdUser) => {
            // Automatically create a personal organization for new users
            const orgId = crypto.randomUUID()
            const memberId = crypto.randomUUID()
            const now = new Date()

            // Create personal organization
            await db.insert(organizationTable).values({
              id: orgId,
              name: `${createdUser.name}'s Workspace`,
              slug: `${createdUser.name.toLowerCase().replace(/\s+/g, "-")}-${Date.now()}`,
              createdAt: now,
              updatedAt: now,
            })

            // Add user as owner
            await db.insert(member).values({
              id: memberId,
              userId: createdUser.id,
              organizationId: orgId,
              role: "owner",
              createdAt: now,
            })
          },
        },
      },
    },
    plugins: [
      organization({
        // Enable teams/sub-organizations
        teams: {
          enabled: true,
          maximumTeams: 10, // Limit teams per organization
          allowRemovingAllTeams: false, // Prevent removing the last team
        },
        // Organization creation settings
        organizationCreation: {
          disabled: false,
          afterCreate: async () => {
            // Set up default resources for manually created organizations
            // Could add default resources, notifications, etc. here in the future
          },
        },
      }),
    ],
    trustedOrigins: [
      ...new Set(
        [
          env.CORS_ORIGIN,
          env.BETTER_AUTH_URL,
          // Canonical production origins — always trusted regardless of env
          "https://openwrite.iliareingold.com",
          "https://openwrite.ilia-reingold.workers.dev",
          // Local development: vite (3001) + wrangler (3000), and the
          // hostname wrangler dev simulates from the custom_domain route
          "http://localhost:3001",
          "http://localhost:3000",
          "http://openwrite.iliareingold.com",
        ].filter(Boolean)
      ),
    ],
    emailVerification: {
      sendOnSignUp: true,
      sendVerificationEmail: async ({ user: recipient, url }) => {
        await sendActionEmail({
          to: recipient.email,
          subject: "Verify your OpenWrite email",
          body: `Hi ${recipient.name || "there"}, confirm your email address to finish setting up your OpenWrite account.`,
          actionUrl: url,
          actionLabel: "Verify email",
        })
      },
    },
    emailAndPassword: {
      enabled: true,
      sendResetPassword: async ({ user: recipient, url }) => {
        await sendActionEmail({
          to: recipient.email,
          subject: "Reset your OpenWrite password",
          body: `Hi ${recipient.name || "there"}, we received a request to reset the password for your OpenWrite account.`,
          actionUrl: url,
          actionLabel: "Reset password",
        })
      },
    },
    advanced: {
      ipAddress: {
        // Cloudflare sets the real client IP here; required for rate limiting
        ipAddressHeaders: ["cf-connecting-ip"],
      },
    },
    secret: env.BETTER_AUTH_SECRET,
    baseURL: env.BETTER_AUTH_URL,
  })
}

let authInstance: ReturnType<typeof buildAuthInstance> | null = null

export function createAuthInstance(env: AuthEnv) {
  if (authInstance) {
    return authInstance
  }

  // Validate required environment variables
  const requiredVars = [
    { name: "CORS_ORIGIN", value: env.CORS_ORIGIN },
    { name: "BETTER_AUTH_SECRET", value: env.BETTER_AUTH_SECRET },
    { name: "BETTER_AUTH_URL", value: env.BETTER_AUTH_URL },
  ]

  const missingVars = requiredVars.filter((envVar) => !envVar.value)

  if (missingVars.length > 0) {
    const missing = missingVars.map((envVar) => envVar.name).join(", ")
    throw new Error(
      `Missing required environment variables for authentication: ${missing}. ` +
        "Please set these variables before starting the server."
    )
  }

  authInstance = buildAuthInstance(env)
  return authInstance
}

// For backward compatibility, export a function that gets the auth instance
export const getAuth = (env: AuthEnv) => createAuthInstance(env)

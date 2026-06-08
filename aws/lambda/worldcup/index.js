// =============================================================================
// AWS Lambda — World Cup 2026 (mocked) API + Swagger UI
// -----------------------------------------------------------------------------
// Routes (matched against `event.rawPath` from API Gateway HTTP API v2):
//   GET /teams           -> Hard-coded World Cup 2026 JSON (auth required)
//   GET /openapi.json    -> OpenAPI 3 spec (auth required)
//   GET /swagger         -> Swagger UI HTML (auth required)
//   GET /health          -> Unauthenticated liveness probe (mounted at $default)
//
// All non-/health routes require a valid AWS Cognito-issued JWT; the
// HTTP API JWT authorizer rejects unauthenticated requests with 401 before
// they ever reach this Lambda.
// =============================================================================

"use strict";

const WORLD_CUP_PAYLOAD = {
    tournament: "FIFA World Cup 2026",
    hostCountries: ["United States", "Canada", "Mexico"],
    groups: [
        { group: "A", teams: ["United States", "Germany", "Japan", "Mexico"] },
        { group: "B", teams: ["Brazil", "France", "England", "South Korea"] }
    ],
    responseType: "AWS API Gateway response",
    authentication: "AWS Cognito JWT (federated via AWS IAM Identity Center / Entra ID in production)",
    source: "aws/lambda/worldcup"
};

// Inline OpenAPI 3 spec — kept tiny so the Lambda has zero dependencies.
function buildOpenApi(host) {
    return {
        openapi: "3.0.3",
        info: {
            title: "World Cup 2026 (AWS, mocked)",
            version: "1.0.0",
            description:
                "Returns a static FIFA World Cup 2026 JSON payload. Secured by AWS Cognito JWT authorizer in front of API Gateway HTTP API."
        },
        servers: [{ url: `https://${host}`, description: "API Gateway stage URL" }],
        components: {
            securitySchemes: {
                CognitoJwt: {
                    type: "http",
                    scheme: "bearer",
                    bearerFormat: "JWT",
                    description: "Cognito User Pool-issued JWT. Acquire via AWS SSO / OAuth2 client credentials."
                }
            }
        },
        security: [{ CognitoJwt: [] }],
        paths: {
            "/teams": {
                get: {
                    summary: "Get World Cup 2026 teams",
                    description: "Returns a hard-coded list of host countries and groups.",
                    responses: {
                        "200": {
                            description: "World Cup payload",
                            content: { "application/json": { schema: { type: "object" } } }
                        },
                        "401": { description: "Missing or invalid JWT" }
                    }
                }
            },
            "/swagger": {
                get: {
                    summary: "Swagger UI",
                    description: "Interactive API explorer.",
                    responses: { "200": { description: "HTML page" } }
                }
            },
            "/openapi.json": {
                get: {
                    summary: "OpenAPI spec",
                    responses: {
                        "200": {
                            description: "OpenAPI 3 document",
                            content: { "application/json": { schema: { type: "object" } } }
                        }
                    }
                }
            },
            "/health": {
                get: {
                    summary: "Liveness probe (unauthenticated)",
                    security: [],
                    responses: { "200": { description: "ok" } }
                }
            }
        }
    };
}

function swaggerHtml(host) {
    return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>World Cup 2026 API — Swagger UI</title>
    <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
  </head>
  <body>
    <div id="swagger"></div>
    <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
    <script>
      window.onload = () => {
        window.ui = SwaggerUIBundle({
          url: "https://${host}/openapi.json",
          dom_id: "#swagger",
          deepLinking: true,
          presets: [SwaggerUIBundle.presets.apis],
          layout: "BaseLayout",
          requestInterceptor: (req) => {
            const t = window.localStorage.getItem("authToken");
            if (t) { req.headers["Authorization"] = "Bearer " + t; }
            return req;
          }
        });
      };
    </script>
    <p style="margin:1rem 2rem;color:#555">
      Tip: paste a Cognito JWT into <code>localStorage.authToken</code> in your
      browser dev tools to authenticate Swagger UI calls.
    </p>
  </body>
</html>`;
}

function reply(statusCode, body, headers = {}) {
    const isJson = typeof body === "object";
    return {
        statusCode,
        headers: {
            "Content-Type": isJson ? "application/json" : "text/html; charset=utf-8",
            "Cache-Control": "no-store",
            ...headers
        },
        body: isJson ? JSON.stringify(body) : body
    };
}

exports.handler = async (event) => {
    const path = (event.rawPath || "/").toLowerCase();
    const host =
        event.requestContext &&
        event.requestContext.domainName &&
        event.requestContext.stage
            ? `${event.requestContext.domainName}/${event.requestContext.stage}`.replace(/\/+$/g, "")
            : "example.execute-api.us-east-1.amazonaws.com";

    if (path.endsWith("/health")) {
        return reply(200, { status: "ok", service: "worldcup-aws" });
    }
    if (path.endsWith("/teams")) {
        return reply(200, WORLD_CUP_PAYLOAD);
    }
    if (path.endsWith("/openapi.json")) {
        return reply(200, buildOpenApi(host));
    }
    if (path.endsWith("/swagger") || path.endsWith("/swagger/")) {
        return reply(200, swaggerHtml(host));
    }

    return reply(404, { error: "not_found", path: event.rawPath });
};

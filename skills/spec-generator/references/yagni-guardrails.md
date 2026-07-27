# YAGNI Guardrails

Use these guardrails whenever spec-generator decides whether a capability belongs in a specification.

## Exclude Unless Requested or Discussed

### Authentication and Authorization

- Complex permission management when basic authentication suffices
- Role-based access control with multiple roles when admin and user are enough
- Social login when basic email and password authentication is sufficient
- Fine-grained permission systems

### Analytics and Monitoring

- Advanced analytics or reporting dashboards
- Detailed audit logging without a compliance requirement
- Real-time metrics and monitoring
- User behavior tracking
- A/B testing infrastructure

### Infrastructure and Scalability

- Multi-tenant support unless explicitly required
- API versioning without an external integration requirement
- Async processing without a performance requirement
- Batch processing or scheduled jobs unless specified
- Auto-scaling infrastructure
- Load-balancing configuration

### User Experience

- Real-time notifications or updates unless explicitly required
- Advanced search or filtering when basic search suffices
- Data export features such as PDF or spreadsheet output
- Offline mode
- Push notifications

### Development and Operations

- Data migration plans for a brand-new project
- Multi-language or internationalization support unless specified
- Admin dashboards when simple CRUD interfaces suffice
- Complex deployment pipelines
- Automated backup systems

## Include by Default

- Basic email and password authentication
- Simple CRUD operations
- Basic error handling and validation
- Essential security such as HTTPS, password hashing, and input sanitization
- Core business logic only
- Simple, clear user interfaces
- Basic data persistence

When the request does not settle a boundary, ask via AskUserQuestion instead of adding the capability.

## Optional Enhancements

When advanced analysis tools are available, consider them for systematic
analysis of interconnected requirements, framework-specific pattern lookup,
existing-code semantic and symbol analysis, and UI/UX pattern recommendations.

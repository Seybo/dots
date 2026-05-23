# Popmenu Development Rules

These rules apply automatically when working in Popmenu codebases. Universal Ruby/Rails conventions (specs, performance, base security) live in [ruby-general.md](ruby-general.md) and apply globally; the rules below are Popmenu-specific — frameworks, libraries, naming conventions, or stack choices unique to Popmenu projects.

## Ruby/Rails

### Services
- Always `include ServiceObject` in service classes (the Popmenu mixin). General service-object guidance is in [ruby-general.md](ruby-general.md#services).

### Sidekiq Jobs
- Always include `unique_for` option
- Always specify `queue` (not `system` or `default` without reason)
- Long-running jobs must be idempotent

### GraphQL
- Mutations must check `authorized?` via Pundit
- Use `GraphInputType` for input validation
- No business logic in resolvers - delegate to services
- After changing `.gql` files, remind to run `yarn graphql-codegen`

### Specs
- Use FactoryBot for test data (Popmenu's chosen factory library).

### Feature Flags
- Use `PopmenuRollout.active?(:flag_name, restaurant)`
- Implement BOTH branches (new and old behavior)
- Test both flag states in specs

## React/TypeScript

### Components
- Define as functions, not `React.FC`
- No `defaultProps` or `PropTypes` - use TypeScript + default args
- Use `@popmenu/common-ui` or `@popmenu/admin-ui` components

### Styling
- Use JSS with `useStyles()` hook
- Use `theme.spacing()` for sizes
- Use `theme.palette` for colors
- No inline `style` attributes

### Localization
- Use `useMessages` pattern for multiple strings
- `FormattedMessage` or `useIntl` for simple cases
- No hardcoded user-facing strings

### Tests
- Use `SetupProviders` from `~/utils/testUtils`
- Check 2+ similar examples before creating new mock patterns

## Security (Rails-specific)

- No `params.permit!`
- Pundit authorization on all mutations

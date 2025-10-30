# Claude Code Configuration for Jitsi Infrastructure

This directory contains Claude Code configuration for working with the Jitsi infrastructure provisioning repository.

## Custom Agents

### jitsi-loki-debugger

A specialized agent for querying and analyzing Jitsi infrastructure logs from Loki. This agent is automatically invoked when investigating:
- Infrastructure errors and issues
- Deployment problems
- Application logs across regions
- Connectivity and performance issues

The agent is located at `.claude/agents/jitsi-loki-debugger.md` and is automatically available when using Claude Code in this repository.

## MCP Server Configuration

To enable Loki log queries, you need to configure the jitsi-loki MCP server in your Claude Code settings.

### Adding the Jitsi Loki MCP Server

The jitsi-loki MCP server is provided as an HTTP service (SSE mode) that you connect to based on your region.

#### Method 1: Command Line (Recommended)

Add the MCP server using the Claude CLI:

**For EU users:**
```bash
claude mcp add -t http jitsi-loki https://ops-prod-eu-frankfurt-1-loki-mcp.jitsi.net/stream
```

**For US users:**
```bash
claude mcp add -t http jitsi-loki https://ops-prod-us-phoenix-1-loki-mcp.jitsi.net/stream
```

After running the command, restart Claude Code to load the new MCP server.

#### Method 2: Manual Configuration

Alternatively, you can manually add the configuration to your Claude Code settings:

1. **Open Claude Code MCP Settings:**
   - Open Claude Code settings
   - Navigate to the MCP servers section
   - Click "Add MCP Server"

2. **Add the server configuration:**

For EU users:
```json
{
  "mcpServers": {
    "jitsi-loki": {
      "url": "https://ops-prod-eu-frankfurt-1-loki-mcp.jitsi.net/stream"
    }
  }
}
```

For US users:
```json
{
  "mcpServers": {
    "jitsi-loki": {
      "url": "https://ops-prod-us-phoenix-1-loki-mcp.jitsi.net/stream"
    }
  }
}
```

**Note:** Choose the region closest to you for better performance. The MCP server will handle authentication automatically.

### Verifying the Configuration

After adding the MCP server configuration:

1. Restart Claude Code
2. Check that the jitsi-loki MCP server is listed in available MCP servers
3. You should see three available tools:
   - `mcp__jitsi-loki__loki_query`
   - `mcp__jitsi-loki__loki_label_names`
   - `mcp__jitsi-loki__loki_label_values`
4. Try a simple query like: "Check logs for jicofo in prod-8x8"

The jitsi-loki-debugger agent will automatically use the MCP server to query logs.

## Known Environments

The jitsi-loki-debugger agent is configured to work with these environments:

- **lonely**: eu-frankfurt-1, us-phoenix-1
- **ops-prod**: eu-frankfurt-1, us-phoenix-1
- **prod-8x8**: Multiple regions (discovered dynamically)

Each environment has its own Loki endpoint in the format:
`https://<environment>-<region>-loki.jitsi.net`

The MCP server URL you configure is only for the MCP connection itself - the agent will automatically query the correct Loki endpoints for each environment/region.

## Usage Examples

Once configured, you can ask Claude Code to:

- "Query jicofo errors in prod-8x8 eu-frankfurt-1 from this morning"
- "Check JVB logs for conference ID abc123 in lonely"
- "Investigate jitsi-meet errors across all lonely regions"
- "Show me prosody logs from node prod-prosody-01"

The agent will automatically construct efficient Loki queries and provide detailed analysis.

## Troubleshooting

### MCP Server Not Found

If Claude Code can't find the jitsi-loki MCP server:
1. Verify the server is listed in your MCP configuration with the correct URL
2. Check that the URL is accessible (test in browser - should return SSE stream)
3. Ensure you're using `/stream` at the end of the URL
4. Restart Claude Code

### Connection Errors

If you see connection errors:
1. Verify you're on the Jitsi VPN or internal network (if required)
2. Check the MCP server URL is correct for your region
3. Try switching to the other region's MCP server if one is unreachable
4. Check network connectivity

### No Results Returned

If queries return no results:
1. Verify the environment and region combination is correct
2. Check the time range (use smaller windows)
3. Verify the node or task name is correct
4. The agent will automatically suggest adjustments

### Tools Not Appearing

If the MCP tools don't show up:
1. Verify the URL ends with `/stream`
2. Check MCP server status in Claude Code settings
3. Look for error messages in Claude Code logs
4. Restart Claude Code completely

## Security Notes

- The MCP server handles authentication automatically
- No credentials need to be stored in your configuration
- Access is controlled at the network/VPN level
- The MCP server configuration is stored in your local Claude Code settings, not in this repository

## Additional Resources

- [Claude Code MCP Documentation](https://docs.claude.com/en/docs/claude-code/mcp)
- [MCP SSE Transport](https://modelcontextprotocol.io/docs/concepts/transports#sse)
- [Grafana Loki Query Language (LogQL)](https://grafana.com/docs/loki/latest/logql/)
- Jitsi Infrastructure Documentation: (add internal link if available)

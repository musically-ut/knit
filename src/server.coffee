http = require 'http'
p    = require 'path'
log  = require './log'

cleanResources = (resources) ->
  # Ensure paths start with '/'
  rs = {}
  rs[p.resolve '/', path] = handler for path, handler of resources
  rs

exports.serve = (config, resources) ->
  config            ?= {}
  config?.port      ?= 8081
  config?.proxyPort ?= 8080
  config?.host      ?= '127.0.0.1'
  config?.proxyHost ?= '127.0.0.1'
  proxyName = "#{ config.proxyHost }:#{ config.proxyPort }"

  if typeof(resources) == 'function'
    loadResources = -> cleanResources resources()
  else
    cleaned = cleanResources resources
    loadResources = -> cleaned

  startServer config, loadResources

  # TODO: Write a previewer which reads content and headers to a memory stream
  log.info "Knit serving at #{ config.host }:#{ config.port }:"
  log.info "#{ path }" for path, handler of loadResources() # TODO: mime-type and size
  log.info "otherwise proxy for #{ proxyName }"

startServer = (config, loadResources) ->
  proxyName = "#{ config.proxyHost }:#{ config.proxyPort }"
  http.createServer((req, res) ->
    resources = loadResources()
    url = req.url
    if req.url of resources # then we should handle the request
      # Print status message for Knit request
      req.on('end', () -> log.info "#{ req.method } #{ req.url }")
      # Set default headers before passing on to handler
      res.setHeader('Cache-Control', 'no-cache')
      res.setHeader('Content-Type', 'text/plain')
      # Serve resources specified in resources
      handler = resources[url]
      # Add convenience method to set mime-type
      res.setMime = (mime) -> this.setHeader('Content-Type', mime)
      res.endWithMime = (data, mime) ->
        this.setHeader('Content-Type', mime)
        this.end(data)
      handler res
    else # pass request on to proxy
      # Print status message for Proxy request
      req.on('end', () -> log.debug "#{ req.method } #{ proxyName }#{ req.url }")
      # Set proxy request details
      poptions =
        host: config.proxyHost
        port: config.proxyPort
        path: req.url
        method: req.method
        headers: req.headers
      # Make proxy request
      preq = http.request poptions, (pres) ->
        res.writeHead pres.statusCode, pres.headers
        pres.on('data', (chunk) -> res.write chunk, 'binary')
        pres.on('end', () -> res.end())
      preq.on 'error', (e) ->
        log.debug "Possible socket close (ignored): #{ JSON.stringify e }"
        log.error "#{ e.message } (#{ req.method } #{ proxyName }#{ req.url })"
        res.writeHead(500, e.code)
        res.end("Proxy connection error: #{ e }\n", "utf8")
      req.on('data', (chunk) -> preq.write chunk, 'binary')
      req.on('end', () -> preq.end())
  ).listen(config.port, config.host)

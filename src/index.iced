Contextify = require 'contextify'
express = require 'express'
domino = require 'domino'
path = require 'path'
fs = require 'fs'
_ = require 'underscore'
url = require 'url'
sockjs = require 'sockjs'
{Map, WeakMap, Set} = require 'es6-collections'
shoe = require 'shoe'
WebSocket = require 'ws'
domain = require 'domain'

requirejs_source = fs.readFileSync "#{__dirname}/client/require.js", 'utf8'
almondjs_source = fs.readFileSync "#{__dirname}/client/almond.js", 'utf8'

if process.env.NODE_ENV is 'production'
	requirejs_source = minify requirejs_source
	almondjs_source = minify almondjs_source

# HANDLER
class Portmanteau
	constructor: ->
		@server = express()
		@Contexts = new WeakMap
		@cache = {}
		@packages = []

	loadScript: (req) => (context, moduleName, url) =>
		console.log(moduleName)
		if url[0] is '/'
			url = url[1...]
		location = path.resolve @dir, url
		await fs.exists location, defer exists
		if !exists then throw new Error "#{location} does not exist"
		await fs.readFile location, 'utf8', defer err, source
		if (url.indexOf('components') isnt -1) and source.indexOf('define(') is -1
			deps = ['require', 'exports', 'module']
			for pack in @config.packages
				if pack.name is moduleName and pack.dependencies?
					deps = deps.concat(pack.dependencies)
					break
			if @config?.shim?[moduleName]?.export?
				source = source + "define(#{@config.shim[moduleName].export})"
			else
				source = "define(#{JSON.stringify(deps)}, function(require, exports, module){var define = undefined; #{source} ; return})"
		environment = @Contexts.get req
		environment.run source
		context.completeLoad moduleName

	createContext: (req, res, next) ->
		context = Contextify domino.createWindow '<!DOCTYPE html>'
		context.Element = require('domino/lib/element')
		context.SERVER =
			res:res
			req:req
			next:next
		context.navigator =
			userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_6_7) AppleWebKit/534.24 (KHTML, like Gecko) Chrome/11.0.696.57 Safari/534.24'
			appName: 'node'
			platform: 'node'
		context.history =
			pushState: ->
			replaceState: ->
		context.console = console
		context.addEventListener = (event, cb) ->
			if event is 'DOMContentLoaded' then cb() else return
		context.setTimeout = (func, delay) ->
			if delay is 0
				timer = process.nextTick
			else
				timer = setTimeout
			timer ->
				func()
			, delay
		context.clearTimeout = clearTimeout
		context.window = context
		self = this
		context.WebSocket = (uri) -> new WebSocket 'ws://localhost:3000/socket/websocket'
		if req?
			context.location = url.parse 'http://' + req.headers.host + req.url + '#'
			context.location.search = ''
			context.document.location = context.location
		context.run requirejs_source
		context.require.load = @loadScript req
		@Contexts.set req, context
		return context

	setupPackages: (json) ->
		for name, version of json.dependencies then do =>
			child = require path.join @dir, 'components', name, 'component.json'
			if child.scripts?[0]?
				subdir = path.dirname child.scripts[0]
			else if child.main?
				subdir = path.dirname child.main
			else
				subdir = ''
			obj =
				name: name
				location: path.join 'components', name, subdir
				main: (if child.scripts?[0]?
					path.basename child.scripts[0]
				else if child.main?
					path.basename child.main
				else if @config.shim?[name]?.main?
					@config.shim[name].main
				else
					'index.js'
				)
				dependencies: []
			@packages.push obj
			for key, val of child.dependencies then obj.dependencies.push key
			if @config.shim[name]? and @config.shim[name].deps?
				for key in @config.shim[name].deps
					obj.dependencies.push(key) if !child?.dependencies?[key]?
			@setupPackages child

	load: (@dir) ->
		@scripts = express.static @dir
		@config = require path.join @dir, 'config.json'
		@setupPackages require path.join @dir, 'component.json'
		@config = _(@config).extend(packages:@packages)
		@server.get '/require.js', (req, res, next) =>
			res.send requirejs_source + "require.config({packages:#{JSON.stringify @packages}, baseUrl:'/requirejs'})"
		@server.get '/requirejs/*', (req, res, next) =>
			script = req.params[0]
			extension = path.extname script
			name = script.replace extension, ''
			await fs.exists path.join(@dir, script), defer exists
			if !exists
				console.error "#{script} doesnt exist"
			await fs.readFile path.join(@dir, script), 'utf8', defer err, data
			for pack in @packages
				if pack.location is path.dirname(script)
					deps = ['require', 'exports', 'module'].concat pack.dependencies
					res.send "define(#{JSON.stringify deps}, function(require, exports, module){var define = undefined; #{data} ; return exports})"
					return
			if data.indexOf('define(') is -1
				data = "define(require, exports, module, function(){ #{data} })"
			res.send data
		@server.get '/components/*', (req, res, next) =>
			script = req.params[0]
			await fs.readFile path.join(@dir, 'components', script), 'utf8', defer err, data
			deps = ['require', 'exports', 'module']
			res.send "define(#{JSON.stringify deps}, function(require, exports, module){var define = undefined; #{data} ; return exports})"
			return
		@server.use (req, res, next) =>
			d = domain.create()
			d.on 'error', (e) ->
				console.error "Error on request: #{e}"
				console.error e.stack
			d.run =>
				context = @createContext req, res, next
				mods = context.require.s.newContext()
				mods.configure @config
				mods.require ['main'], ->
				res.once 'end', => @Contexts.del req

	listen: ->
		handle = @server.listen.apply @server, arguments
		sock = shoe (@Stream or ->)
		sock.install handle, '/socket'

module.exports = Portmanteau

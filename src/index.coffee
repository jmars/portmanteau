Contextify = require 'contextify'
{wrap, wait} = Future = require 'fibers/future'
express = require 'express'
domino = require 'domino'
path = require 'path'
fs = require 'fs'
_ = require 'underscore'
url = require 'url'
Remote = require 'remote'
request = require 'request'
sockjs = require 'sockjs'
{Map, WeakMap, Set} = require 'es6-collections'

requirejs_source = fs.readFileSync "#{__dirname}/client/require.js", 'utf8'
almondjs_source = fs.readFileSync "#{__dirname}/client/almond.js", 'utf8'

if process.env.NODE_ENV is 'production'
	requirejs_source = minify requirejs_source
	almondjs_source = minify almondjs_source

class Portmanteau
	constructor: ->
		@server = express()
		@Contexts = new WeakMap
		@cache = {}
		@components = {}
		@packages = []

	loadScript: (context, moduleName, url) =>
		location = path.resolve @dir, url
		future = new Future
		fs.readFile location, 'utf8', (err, data) => 
			if err
				future.throw err
			else
				if url.indexOf('components') isnt -1
					future.return "define(function(require, exports, module){var define = undefined; #{data} ; return exports})"
				else
					future.return data
		source = future.wait()
		environment = @Contexts.get Fiber.current
		environment.run source
		context.completeLoad moduleName

	createContext: (req, res, next) ->
		if !@layout?
			html = '<!DOCTYPE html>'
		else
			future = new Future
			@layout req, res, next, (err, html) -> future.return html
			html = future.wait()
		context = Contextify domino.createWindow html
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
			future = new Future
			if delay is 0
				timer = process.nextTick
			else
				timer = setTimeout
			timer ->
				future.return()
			, delay
			future.wait()
			func()
		context.window = context
		context.WebSocket = @wsclient
		if req?
			context.location = url.parse 'http://' + req.headers.host + req.url + '#'
			context.location.search = ''
			context.document.location = context.location
		context.run requirejs_source
		context.require.load = @loadScript
		@Contexts.set Fiber.current, context
		return context

	RPC: {}

	setupPackages: (json) ->
		for name, version of json.dependencies then do =>
			location = name.replace '/', '-'
			name = name.split('/')[1]
			child = require path.join @dir, 'components', location, 'component.json'
			subdir = path.dirname child.scripts[0]
			obj =
				name: name
				location: path.join 'components', location, subdir
				main: path.basename child.scripts[0]
				dependencies: []
			length = @packages.push obj
			for key, val of child.dependencies then obj.dependencies.push key.split('/')[1]
			@components[name] = length-1
			@setupPackages child

	load: (@dir) ->
		@scripts = express.static @dir
		@setupPackages require path.join @dir, 'component.json'
		@server.get '/require.js', (req, res, next) =>
			res.send requirejs_source + "require.config({packages:#{JSON.stringify @packages}, baseUrl:'/requirejs'})"
		@server.get '/requirejs/*', (req, res, next) =>
			script = req.params[0]
			extension = path.extname script
			name = script.replace extension, ''
			fs.readFile path.join(@dir, script), 'utf8', (err, data) =>
				for pack in @packages
					if pack.location is path.dirname(script)
						deps = ['require', 'exports', 'module'].concat pack.dependencies
						res.send "define(#{JSON.stringify deps}, function(require, exports, module){var define = undefined; #{data} ; return exports})"
						return
				res.send data
		@server.use (req, res, next) =>
			Fiber =>
				context = @createContext req, res, next
				mods = context.require.s.newContext()
				mods.configure packages:@packages
				mods.require ['main'], ->
				{current} = Fiber
				if !res.ended
					res.end context.document.innerHTML, =>
						@Contexts.delete current
						current.reset()
						current = {}
				else
					@Contexts.delete current
					current.reset()
					current = {}
			.run()

	listen: ->
		handle = @server.listen.apply @server, arguments
		socket = sockjs.createServer()
		do =>
			RPC = @RPC
			class wsclient
				constructor: (location) ->
					self = @
					@data = ''
					@port = send: (message) ->
						self.data = message
						self.future.return()
					Remote @port, RPC, []
				send: (data) ->
					@future = new Future
					@port.recieve data
					@future.wait()
					@onmessage data:@data
			wsclient::__defineSetter__ 'onopen', (f) -> do f
			@wsclient = wsclient
		socket.on 'connection', (ws) =>
			port = send: (message) -> ws.write message
			ws.on 'data', (data) -> port.recieve data
			ws.on 'close', -> port.close()
			Remote port, @RPC, []
			port.open()
		socket.installHandlers handle, prefix: '/socket'

module.exports = Portmanteau

Contextify = require 'contextify'
express = require 'express'
domino = require 'domino'
path = require 'path'
fs = require 'fs'
_ = require 'underscore'
url = require 'url'
sockjs = require 'sockjs'
{Map, WeakMap, Set} = require 'es6-collections'
{EventEmitter2} = require 'eventemitter2'
shoe = require 'shoe'
dnode = require 'dnode'

requirejs_source = fs.readFileSync "#{__dirname}/client/require.js", 'utf8'
almondjs_source = fs.readFileSync "#{__dirname}/client/almond.js", 'utf8'

if process.env.NODE_ENV is 'production'
	requirejs_source = minify requirejs_source
	almondjs_source = minify almondjs_source

class wsclient
	constructor: (location) ->
		#@dnode = dnode @root.RPC
		#@dnode.on 'data', (d) => @write d
	send: (data) ->
		#@dnode.write data
	write: (data) ->
		#@onmessage data:data
wsclient::__defineSetter__ 'onopen', (f) -> process.nextTick -> do f

# HANDLER
class Portmanteau
	constructor: ->
		@server = express()
		@Contexts = new WeakMap
		@cache = {}
		@components = {}
		@packages = []

	loadScript: (req) => (context, moduleName, url) =>
		if url[0] is '/'
			url = url[1...]
		location = path.resolve @dir, url
		await fs.exists location, defer exists
		if !exists then throw new Error "#{location} does not exist"
		await fs.readFile location, 'utf8', defer err, source
		if url.indexOf('components') isnt -1
			source = "define(function(require, exports, module){var define = undefined; #{source} ; return exports})"
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
		context.WebSocket = class wsconnection extends wsclient
			constructor: ->
				@root = self
				super
		if req?
			context.location = url.parse 'http://' + req.headers.host + req.url + '#'
			context.location.search = ''
			context.document.location = context.location
		context.run requirejs_source
		context.require.load = @loadScript req
		@Contexts.set req, context
		return context

	RCE: null

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
			fs.exists path.join(@dir, script), (exists) =>
				if !exists
					console.error "#{script} doesnt exist"
				fs.readFile path.join(@dir, script), 'utf8', (err, data) =>
					for pack in @packages
						if pack.location is path.dirname(script)
							deps = ['require', 'exports', 'module'].concat pack.dependencies
							res.send "define(#{JSON.stringify deps}, function(require, exports, module){var define = undefined; #{data} ; return exports})"
							return
					res.send data
		@server.get '/components/*', (req, res, next) =>
			script = req.params[0]
			fs.readFile path.join(@dir, 'components', script), 'utf8', (err, data) =>
				deps = ['require', 'exports', 'module']
				res.send "define(#{JSON.stringify deps}, function(require, exports, module){var define = undefined; #{data} ; return exports})"
				return
		@server.use (req, res, next) =>
			context = @createContext req, res, next
			mods = context.require.s.newContext()
			mods.configure packages:@packages
			mods.require ['main'], ->
			res.once 'end', => @Contexts.del req

	listen: ->
		handle = @server.listen.apply @server, arguments
		socket = sockjs.createServer()
		socket.on 'connection', (ws) =>
			ws.on 'data', (data) =>
			ws.on 'close', =>
		socket.installHandlers handle, prefix: '/socket'

module.exports = Portmanteau

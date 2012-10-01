portmanteau = require 'portmanteau'
stylus = require 'stylus'
nib = require 'nib'
express = require 'express'
jade = require 'jade'

server = express()

await jade.renderFile "#{__dirname}/pages/layout.jade", defer err, layout

compile = (str, path) ->
	stylus(str)
	.set('filename', path)
	.set('compress', true)
	.use(nib())

app = new portmanteau
app.server.configure 'production', ->
  app.server.use express.compress()
app.server.use express.favicon()
app.server.use stylus.middleware
  src: "#{__dirname}/assets"
  compile: compile
app.server.use express.static "#{__dirname}/assets"
app.load __dirname
app.layout = (req, res, next, cb) -> cb null, layout

app.listen 3000, ->
  console.log 'server started'
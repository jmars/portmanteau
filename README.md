# Portmanteau
[![endorse](http://api.coderwall.com/jmars/endorsecount.png)](http://coderwall.com/jmars)

Portmanteau is a framework for building applications that run the same on both the server and in browsers. It is an attempt to solve the problem of rewriting code to do the same thing on both the server and client. Currently it supports the DOM and has a module system that can use [components](http://github.com/component/component) as well as the WebSocket API that properly works when doing asynchronous work.

Currently there is a built in RPC system that needs to be abstracted.

## Planned
* HTML5 Canvas Support
* LocalStorage Support
* SVG Support
* Complete HTML5 History API (Currently works partially)

This is not ready to be used yet, please don't try to use this and then start complaining about bugs. It's likely that once this is complete
I will fork it and rewrite it cleanly.
define([], function(){
	if (typeof SERVER !== 'undefined') {
		SERVER.res.end('hello world');
	} else {
		document.body.innerText = 'hello world';
	}
});
(function($) {
    $.fn.probe = function(options, manual) {
  
	var graph_options = $.extend(true, {
	    legend: {
		container: this.find('.legend').get(0),
		position: 'ne'
	    },
	    title: options['title'],
	    subtitle: options['desc'],
	    HtmlText: false,
	    xaxis: { mode: 'time' },
	    yaxis: { },
	    selection : { mode : 'xy', fps : 30 }
	}, options['options']), // Flotr2 options, merge with our defaults
	legend = this.find('.legend'),
	graph, // Flotr2 graph object
	data, // the data to feed Flotr2
	container = this.find('.graph').get(0),
	legend = this.find('.legend');
	d = this.find('.debug');

	function debug(bla) {
	    d.append('<p>' + JSON.stringify(bla) + '</p>');
	}

	// get the data with ajax
	function getData(opts) {
	    // { id_graph: options['id'], nsp: options['namespace'] },
	    $.post('/draw/data',
		   opts,
		   function (series) {
		       if (series.error != null) {
			   alert("error: " + series.error);
			   return;
		       }

		       data = series['data'];
		       graph_options['xaxis']['min'] = series['scale']['xmin'];
		       graph_options['xaxis']['max'] = series['scale']['xmax'];
		       if (parseInt(series['scale']['ymin']) >= 0) {
			   graph_options['yaxis']['min'] = 0;
		       } else {
			   graph_options['yaxis']['min'] = series['scale']['ymin'];
		       }
		       graph_options['yaxis']['max'] = series['scale']['ymax'];
		       
		       graph = drawGraph(graph_options);
		   },
		   'json'
		  );
	}

	if (manual == null) {
	    getData({ id_graph: options['id'], nsp: options['namespace'] });
	}

	// Draw the graph
	function drawGraph(opts) {
	    var o = Flotr._.extend(Flotr._.clone(graph_options), opts || {});

	    // Drawing the graph multiple time appends labels to the
	    // legend when it is in an external div. So empty it
	    // before drawing
	    if (o['legend']['container'] != null) {
		legend.contents().empty();
	    }
	    return Flotr.draw(container, data, o);
	}

	// Save action
	$('#save' + options['id']).click(function (event) {
	    event.preventDefault();
	    graph.download.saveImage('png');
	});

	// Selection
	// Hook into the 'flotr:select' event.
	Flotr.EventAdapter.observe(container, 'flotr:select', function (area) {
	    
	    var new_min = area.x1 + parseInt(graph_options['xaxis']['min']),
	    new_max = area.x2 + parseInt(graph_options['xaxis']['min']);

	    // Draw graph with new area
	    graph = drawGraph({
		xaxis: {mode: 'time', min: new_min, max: new_max },
		yaxis: {min:area.y1, max:area.y2}
	    });

	});
    
	// When graph is clicked, draw the graph with default area.
	Flotr.EventAdapter.observe(container, 'flotr:click', function () {
	    graph = drawGraph();
	});
					      
	return this;				      
  };
})(jQuery);

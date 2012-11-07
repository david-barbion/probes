/*
 * probe.js -- JQuery Plugin to draw graphs using Flotr2 and ajax to
 * get the data
 */

(function($) {
  $.fn.probe = function(options) {
    var defaults = {
      controls: null, // element storing the controls to modify the flotr2 options
      saveDiv: null, // parent element for a link/button for saving
		     // the graph as an image, only the first save
		     // button is put there
      drawButton: null, // a link/button to draw the graph, if null draw right away
      data: {
	namespace: null,
	id: null,
      },
      options: {
	shadowSize: 0,
	legend: {
          position: 'ne'
	},
	HtmlText: false,
	xaxis: {
          mode: 'time',
          timeFormat: "%d/%m/%y\n%H:%M:%S",
	  autoscaleMargin: 5
	},
	yaxis: { },
	selection : { mode : 'xy', fps : 30 },
	mouse: {
	  track: true,
	  trackAll: true,
	  sensitivity: 4,
	  relative: true,
	  trackFormatter: function (coor) {
	    var d = new Date (parseInt(coor.x));
	    return '<span style="font-size:0.8em;text-align:center;">'+
	      d.getDate() +'/'+ (d.getMonth()+1) + '/' + d.getFullYear() +'<br/>'+
	      d.getHours()+':'+d.getMinutes()+':'+d.getSeconds() + '<br />' + coor.y +
	      '</span>';
	  }
	}
      },
      title: null,
      desc: null
    },
    settings,
    data,
    zone = this,
    clicked;
    

    settings = $.extend(true, {}, defaults, options);
    settings.options.title = settings.title;
    delete settings.title;
    settings.options.subtitle = settings.desc;
    delete settings.desc;


    function updateGraphOptions() {

      // get all the controls values, update the options and draw
      if (settings.controls !== null) {
	if ($(settings.controls).find('input[name=graph-type]:checked').val() == 'lines') {
	  delete settings.options.points;
	  delete settings.options.pie;
	  settings.options['lines'] = {
            show: true,
            fill: ($(settings.controls).find('#filled:checked').length == 1),
            lineWidth: parseFloat($('input[name=series-width]').val()),
            stacked: ($(settings.controls).find('#stacked:checked').length == 1? true:null)
	  };
	}
	else if ($(settings.controls).find('input[name=graph-type]:checked').val() == 'points') {
	  delete settings.options.lines;
	  delete settings.options.pie;
	  settings.options['points'] = {
            show: true,
            fill: ($(settings.controls).find('#filled:checked').length == 1),
            lineWidth: parseFloat($('input[name=series-width]').val()),
            stacked: ($(settings.controls).find('#stacked:checked').length == 1? true:null)
	  };
	}
	else {
	  delete settings.options.lines;
	  delete settings.options.points;
	  settings.options['pie'] = {
            show: true,
            fill: ($(settings.controls).find('#filled:checked').length == 1),
            lineWidth: parseFloat($('input[name=series-width]').val()),
            stacked: ($(settings.controls).find('#stacked:checked').length == 1? true:null)
	  };
	}

	settings.options.title = $(settings.controls).find('#name').val() || '';
	settings.options.subtitle = $(settings.controls).find('#desc').val() || '';
      }
    }

    function controlAction() {
      if (data)
	drawAllGraphs();
      else
	getData({
	  query: $(settings.controls).find('#query').val(),
	  namespace: $(settings.controls).find('select[name=nsp]').val(),
	  filter_query:  $(settings.controls).find('#filter_query').val()
	});
    }

    function setupControls() {
      // get all the controls values, update the options and draw
      if (settings.controls !== null) {

	$(settings.controls).find('input[type="checkbox"]').change(function () {
	  controlAction();
	});
	$(settings.controls).find('input[type="radio"]').change(function () {
	  controlAction();
	});
	$(settings.controls).find(settings.controls).find('input[name=legend-cols]').change(function () {
	  controlAction();
	});
	$(settings.controls).find('input[name=series-width').change(function () {
	  controlAction();
	});
      }
    }


    function getData(opts) {
      /* get the series data with ajax
	 [ { filter: [ val1, val2 ],
	     series: [ { label: "str", data: [ [x1, y1], [x2, y2 ] ] } ]
         ]
       */

      $.post('/graphs/data',
	     opts,
	     function (result) {
	       if (result.error != null) {
                 alert("error: " + result.error);
                 return;
               }

	       data = result;
	       drawAllGraphs();
	     },
	     'json');
    }

    function drawAllGraphs() {
      var i, c, o, s;

      // update the options
      updateGraphOptions();

      // reset graph area
      zone.empty();

      // Draw each graph
      for (i = 0; i < data.length; i++) {

	// put the save button in the provided div, only for the first graph
	s = (i == 0) ? true : false;

	if (data[i].filters) {
	  c = drawGraphArea(data[i].filters, s);
	  o = {};
	  o['title'] = settings.options.title + ' ('+ data[i].filters.join(', ')+')';
	} else {
	  c = drawGraphArea(null, s);
	}

	drawGraph(c, data[i].series, o);
      }
    }

    function drawGraphArea(filters, use_save_div) {
      // redraw all the graph placeholders when the filters query changes
      var i, area_id,
      container, save_link = null;

      if (filters !== null) {
	area_id = 'graph_area_' + filters.join('_');
      } else {
	area_id = 'graph_area';
      }

      // Create graph box
      if (settings.saveDiv !== null) {
	// When the target div for the save button is given, add the
	// link to it only when asked
	if (use_save_div === true) {
	  $(settings.saveDiv).append('<a href="#" class="btn btn-mini">Save</a>');

	  zone.append('<div  id="'+area_id+'">'+
		      ' <div class="graph_container">'+
		      '  <div class="graph"></div>'+
		      '  <div class="legend"></div>'+
		      ' </div>'+
		      '</div>');
	} else {
	  zone.append('<div  id="'+area_id+'">'+
		      ' <div class="btn-group pull-right"><a href="#" class="btn btn-mini">Save</a></div>'+
		      ' <div class="graph_container">'+
		      '  <div class="graph"></div>'+
		      '  <div class="legend"></div>'+
		      ' </div>'+
		      '</div>');
	}
      } else {
	zone.append('<div  id="'+area_id+'">'+
		      ' <div class="btn-group pull-right"><a href="#" class="btn btn-mini">Save</a></div>'+
		      ' <div class="graph_container">'+
		      '  <div class="graph"></div>'+
		      '  <div class="legend"></div>'+
		      ' </div>'+
		      '</div>');
      }

      // Remember the container element
      container = zone.find('#'+area_id).find('.graph');

      // Choose the correct save button
      if (settings.saveDiv !== null) {
	if (use_save_div === true) {
	  save_link = $(settings.saveDiv).find('a').filter(":last");
	} else {
	  save_link = zone.find('#'+area_id).find('a');
	}
      } else {
	save_link = zone.find('#'+area_id).find('a');
      }

      // Prepare an empty list to remember zooms
      container.data('zooms', [ ]);

      return { container: container,
	       save: save_link };
    }

    function drawGraph(area, data, opts) {
      // draw a graph with Flotr2
      var o = $.extend(true, {}, settings.options, opts || {}),
      graph,
      container = area.container.get(0);

      graph = Flotr.draw(container, data, o);

      // Bind the save action
      area.save.click(function (event) {
	event.preventDefault();
	graph.download.saveImage('png', null, null, false);
      });

      // Bind the selection
      Flotr.EventAdapter.observe(container, 'flotr:select', function (sel, g) {
	var zoom = {
          xaxis: {
	    min: sel.x1,
	    max: sel.x2
	  },
          yaxis: {
	    min: sel.y1,
	    max: sel.y2
	  }
	},
	zo = $.extend(true, {}, o, zoom);

	// Save the zoom information
	var zl = area.container.data('zooms');
	zl.push(zoom);
	area.container.data('zooms', zl);

	graph = Flotr.draw(container, data, zo);
      });

      // When graph is clicked, draw the graph with default area
      Flotr.EventAdapter.observe(container, 'flotr:click', function () {
	var zl = area.container.data('zooms'),
	zoom, zo;

	// Remove the current zoom information and get the previous
	zl.pop();
	zoom = zl[zl.length-1];

	zo = $.extend(true, {}, o, zoom || { });

	graph = Flotr.draw(container, data, zo);
      });

      return graph;
    }

    if (settings.drawButton === null) {
      getData(settings.data);
    } else {
      $(settings.drawButton).click(function () {
	if (clicked !== true) {
	  setupControls();
	  clicked = true;
	}

	updateGraphOptions();
	getData({
	  query: $(settings.controls).find('#query').val(),
	  namespace: $(settings.controls).find('select[name=nsp]').val(),
	  filter_query:  $(settings.controls).find('#filter_query').val()
	});
      });
    }
  }
})(jQuery);

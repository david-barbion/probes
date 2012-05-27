/*
definition du plugin jquery pour pg_probe
- doit pouvoir afficher un graph en mode show ou add/edit
- merger auditools.js et probe.js

functions:
- init
- create des zones de graphs avec les header footer
- maj/création des options
- recup des data en ajax
- selection
- affichage du graph


utilisation:
- il faut une div pour les graphs, on se branche dessus
{ save: selector,
  controls: selector,
  trigger: selector,
  header: {
    single: 'html',
    multiple: 'html'
  },
  footer: {
    single: 'html',
    multiple: 'html' },
  data: { id: x, namespace: 'y' }
}
  
*/


(function($) {
  $.fn.probe = function(options) {
    var defaults = {
      controls: null, // element storing the controls to modify the flotr2 options
      saveButton: null, // a link/button for saving the graph as an image, will be disabled in multi graphs
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
    zone = this;
    

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

    function setupControls() {
      // get all the controls values, update the options and draw
      if (settings.controls !== null) {

	$(settings.controls).find('input[type="checkbox"]').change(function () {
	  if (data)
	    drawAllGraphs();
	  else
	    getData({
	      query: $(settings.controls).find('#query').val(),
	      namespace: $(settings.controls).find('input[name=nsp]').val(),
	      filter_query:  $(settings.controls).find('#filter_query').val()
	    });
	});
	$(settings.controls).find('input[type="radio"]').change(function () {
	  if (data)
	    drawAllGraphs();
	  else
	    getData({
	      query: $(settings.controls).find('#query').val(),
	      namespace: $(settings.controls).find('input[name=nsp]').val(),
	      filter_query:  $(settings.controls).find('#filter_query').val()
	    });
	});
	$(settings.controls).find(settings.controls).find('input[name=legend-cols]').change(function () {
	  if (data)
	    drawAllGraphs();
	  else
	    getData({
	      query: $(settings.controls).find('#query').val(),
	      namespace: $(settings.controls).find('input[name=nsp]').val(),
	      filter_query:  $(settings.controls).find('#filter_query').val()
	    });
	});
	$(settings.controls).find('input[name=series-width').change(function () {
	  if (data)
	    drawAllGraphs();
	  else
	    getData({
	      query: $(settings.controls).find('#query').val(),
	      namespace: $(settings.controls).find('input[name=nsp]').val(),
	      filter_query:  $(settings.controls).find('#filter_query').val()
	    });
	});
      }
    }


    function getData(opts) {
      /* get the series data with ajax
	 [ { filter: [ val1, val2 ],
	     series: [ { label: "str", data: [ [x1, y1], [x2, y2 ] ] } ]
         ]
       */

      $.post('/draw/data',
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
      var i, c, o;

      // update the options
      updateGraphOptions();

      // reset graph area
      zone.empty();

      // Draw each graph
      for (i = 0; i < data.length; i++) {

	if (data[i].filters) {
	  c = drawGraphArea(data[i].filters);
	  o = {};
	  o['title'] = settings.options.title + ' ('+ data[i].filters.join(', ')+')';
	} else {
	  c = drawGraphArea(null);
	}

	drawGraph(c, data[i].series, o);
      }
    }

    function drawGraphArea(filters) {
      // redraw all the graph placeholders when the filters query changes
      var i, area_id,
      container, save_link = null;

      if (filters !== null) {
	area_id = 'graph_area_' + filters.join('_');
      } else {
	area_id = 'graph_area';
      }

      // Create graph box
      zone.append('<div  id="'+area_id+'" class="block_body">'+
		  '<a href="#" class="link graph_save">Save</a>'+
		  '<div class="graph_container">'+
		  '<div class="graph"></div>'+
		  '<div class="legend"></div>'+
		  '</div>'+
		  '</div>');

      container = zone.find('#'+area_id).find('.graph')

      // Prepare an empty list to remember zooms
      container.data('zooms', [ ]);

      return { container: container,
	       save: zone.find('#'+area_id).find('a') };
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
	graph.download.saveImage('png');
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

    setupControls();

    if (settings.drawButton === null) {
      getData(settings.data);
    } else {
      $(settings.drawButton).click(function () {

	updateGraphOptions();
	getData({
	  query: $(settings.controls).find('#query').val(),
	  namespace: $(settings.controls).find('input[name=nsp]').val(),
	  filter_query:  $(settings.controls).find('#filter_query').val()
	});
      });
    }
  }
})(jQuery);

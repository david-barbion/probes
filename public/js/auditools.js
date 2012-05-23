$(function () {

  jQuery.auditools = {
    data: []
  };

  var graph,
  container = $('#graph_area').get(0);

  function drawGraph(opts) {

    var data = [];
    var options = {
      shadowSize: 5,
      legend: {
        show: ($('input[name=show-legend]:checked').length == 1),
        noColumns: $('input[name=legend-cols]').val(),
        position: 'ne',
      },
      xaxis: {
        mode: 'time',
        timeFormat: "%d/%m/%y %H:%M:%S",
	autoscaleMargin: 1
      },
      yaxis: {

      },
      title: $('#name').val() || null,
      subtitle : $('#desc').val() || null,
      selection: {
        mode: "xy"
      }
    }

    /* disable form submission when using enter in flot options text fields */
    $('#series-width').keypress(function(event) {
      if ( event.which == 13 ) return false;
    });

    $('#legend-cols').keypress(function(event) {
      if ( event.which == 13 ) return false;
    });

    if ($('input[name=graph-type]:checked').val() == 'lines') {
      delete options.points;
      delete options.pie;
      options['lines'] = {
        show: true,
        fill: ($('#filled:checked').length == 1),
        lineWidth: parseFloat($('input[name=series-width]').val()),
        stacked: ($('#stacked:checked').length == 1? true:null)
      };
    }
    else if ($('input[name=graph-type]:checked').val() == 'points') {
      delete options.lines;
      delete options.pie;
      options['points'] = {
        show: true,
        fill: ($('#filled:checked').length == 1),
        lineWidth: parseFloat($('input[name=series-width]').val()),
        stacked: ($('#stacked:checked').length == 1? true:null)
      };
    }
    else {
      delete options.lines;
      delete options.points;
      options['pie'] = {
        show: true,
        fill: ($('#filled:checked').length == 1),
        lineWidth: parseFloat($('input[name=series-width]').val()),
        stacked: ($('#stacked:checked').length == 1? true:null)
      };
    }

    if (!data.length)
      data = jQuery.auditools.data;

    return graph = Flotr.draw(
      container,
      data,
      Flotr._.extend(Flotr._.clone(options), opts || {})
    );

  }

  /* update the graph when changing properties */
  $('#form input[type="checkbox"]').change(function () {
    drawGraph();
  });
  $('#form input[type="radio"]').change(function () {
    drawGraph();
  });
  $('input[name=legend-cols]').change(function () {
    drawGraph();
  });
  
  $('#add_graph').click(function () {
    $.ajax({
      url: '/draw/data',
      type: 'post',
      dataType: 'json',
      data: {
        query: $('#query').val(),
        nsp: $('input[name=nsp]').val()
      },
      success: function (series) {
        if (series.error != null) {
          alert("error:" + series.error);
          return;
        }

        jQuery.auditools.data = series['data'];

        drawGraph();
        
      }
    });
    return false;
  });

  /* update the query textarea when a preset option is selected */
  $('li#presets select').change(function () {
    $('#query').text($(this).val());
  });

  // Selection
  // Hook into the 'flotr:select' event.
  Flotr.EventAdapter.observe(container, 'flotr:select', function (area) {
    
    // Draw graph with new area
    graph = drawGraph({
      xaxis: {
	mode: 'time',
	timeFormat: "%d/%m/%y %H:%M:%S",
	autoscaleMargin: 1,
	min: area.x1,
	max: area.x2
      },
      yaxis: {
	min:area.y1,
	max:area.y2
      }
    });

  });
  
  // When graph is clicked, draw the graph with default area.
  Flotr.EventAdapter.observe(container, 'flotr:click', function () {
    graph = drawGraph();
  });

});

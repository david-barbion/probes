


graph = Flotr.draw(
    container,[ 
      {data:d1, label:'y = 4 + x^(1.5)', lines:{fill:true}}, 
      {data:d2, label:'y = x^3', yaxis:2}, 
      {data:d3, label:'y = 5x + 3sin(4x)'}, 
      {data:d4, label:'y = x'},
      {data:d5, label:'y = 2x', lines: {show: true}, points: {show: true}}
    ],{
      title: 'Download Image Example',
      subtitle: 'You can save me as an image',
      xaxis:{
        noTicks: 7, // Display 7 ticks.
        tickFormatter: function(n){ return '('+n+')'; }, // => displays tick values between brackets.
        min: 1,  // => part of the series is not displayed.
        max: 7.5, // => part of the series is not displayed.
        labelsAngle: 45,
        title: 'x Axis'
      },
      yaxis:{
        ticks: [[0, "Lower"], 10, 20, 30, [40, "Upper"]],
        max: 40,
        title: 'y = f(x)'
      },
      y2axis:{color:'#FF0000', max: 500, title: 'y = x^3'},
      grid:{
        verticalLines: false,
        backgroundColor: 'white'
      },
      HtmlText: false,
      legend: {
        position: 'nw'
      }
  });


















(function($){

    $.stuff = {
	data: [],
    }

    $.fn.graph = function() {
	var data = []



})(jQuery);


function graph_editor() {

    // Un gros pompage de auditools, merci Ioguix

    jQuery.stuff = {
	data: [],
    };

    function drawGraph(from, to) {

        var data = [];
        var options = {
            legend: {
                show: ($('input[name=show-legend]:checked').length == 1),
                noColumns: $('input[name=legend-cols]').val()
            },
            series: {
                stack: ($('#stacked:checked').length == 1? true:null),
            },
            xaxis: { mode: 'time' },
            selection: {
                mode: "x",
                color: "#444"
            }
        }

        if ($('input[name=graph-type]:checked').val() == 'lines') {
            options['series']['lines'] = {
                show: true,
                fill: ($('#filled:checked').length == 1),
                lineWidth: parseFloat($('input[name=series-width]').val())
            };
        }
        else if ($('input[name=graph-type]:checked').val() == 'points') {
            options['series']['points'] = {
                show: true,
                fill: ($('#filled:checked').length == 1),
                radius: parseFloat($('input[name=series-width]').val())
            };
        }
        else {
            options['series']['pie'] = {
                show: true,
            };
        }

        if (from != null)
            options['xaxis'].min = from;

        if (to != null)
            options['xaxis'].max = to;

        $("#legend").find("input:checked").each(function () {
            var key = $(this).attr("name").substring(6);
            if (jQuery.auditools.data[key])
                data.push(jQuery.auditools.data[key]);
        });

        if (!data.length)
            data = jQuery.auditools.data;

        var plot = $.plot(
            $("#graph_area"),
            data,
            options
        );

        $('div.legend').draggable();
        $('#graph_box')
            .draggable({handle: $('.tickLabel')})
            .resizable({
                helper: 'resize-hi',
                stop: function () {
                    drawGraph();
                }
            });

        return plot;
    }

    /* update the graph when changing properties */
    $('#form input:checkbox').click(function () {
       drawGraph();
    });
    $('input[name=legend-cols]').change(function () {
       drawGraph();
    });
    
    $('#add_graph').click(function () {
        $.ajax({
            url: 'graph_datas.php',
            type: 'post',
            dataType: 'json',
            data: {
                query: $('#query').val()
            },
            success: function (series) {
                if (series.error != null) {
                    alert("error:" + series.error);
                    return;
                }

                jQuery.auditools.data = series;

                /* Hardcode the color for each series so they don't change
                   when enabling/disabling and moving them. */
                var i = 0;
                $.each(jQuery.auditools.data, function(key, val) {
                    val.color = i;
                    i++;
                });

                var plot = drawGraph();

                /* build the dynamic legend */
                $('#legend').empty();
                $.each(plot.getData(), function(idx, val) {
                    $('#legend').append('<li class="sortable">'
                        + '<div class="legend-color" id="color-' + idx + '">'
                        + '<div style="background-color: '+ val.color +'"></div></div>'
                        + '<label for="id-serie-' + idx + '">'
                        + '<input type="checkbox" name="serie-'+ idx +'" checked="checked" id="id-serie-'+ idx +'" />'
                        + val.label + '</label></li>');
                });

                /* make the legend sortable */
                if (jQuery.auditools.data.length) {
                    $('#legend')
                        .sortable({
                            update: function(event, ui) {
                                drawGraph();
                            },
                            placeholder: "drag-hi"
                        })
                        .disableSelection();
                }

                /* update the graph with selected series */
                $('#legend').find("input:checkbox").click(function () {
                    drawGraph();
                });
            }
        });
        return false;
    });

    /* handle zoom action */
    $('#graph_area').bind("plotselected", function (event, ranges) {

        // clamp the zooming to prevent eternal zoom
        if (ranges.xaxis.to - ranges.xaxis.from < 0.00001) 
            ranges.xaxis.to = ranges.xaxis.from + 0.00001;
        if (ranges.yaxis.to - ranges.yaxis.from < 0.00001) 
            ranges.yaxis.to = ranges.yaxis.from + 0.00001;

        drawGraph(ranges.xaxis.from.toPrecision(13), ranges.xaxis.to.toPrecision(13));
    });

    $('a.preset').click(function () {
        $('#query').text($(this).find('div.query').text());
        eval($(this).find('script.params').html());

        $.each(params, function (key, val) {
            if (key == 'filled' || key == 'stacked' || key == 'show-legend') {
                if (val)
                    $('input[name='+ key +']').attr('checked', 'checked');
                else
                    $('input[name='+ key +']').removeAttr('checked');
            }
            else if (key == 'graph-type') {
                $('input[name=graph-type]').removeAttr('checked');
                $('input[name=graph-type][value='+ val +']').attr('checked', 'checked');
            }
            else if (key == 'legend-cols' || key == 'series-width') {
                $('input[name='+ key +']').val(val);
            }
        });

        return false;
    });

    drawGraph();
};
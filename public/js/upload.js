(function() {
    
  var container = $('#upload-status');
  var bar = container.find('.bar');
  var status = container.find('.status');
  var buttons = container.find('.after');

  container.hide();

  $('#fileupload').ajaxForm({
    beforeSend: function() {

      // Swap the controls
      $('#fileupload').hide();
      container.show();
      buttons.hide();

      // Initialize the progress bar
      status.empty();
      var percentVal = '0%';
      bar.width(percentVal)

      // Put form contents inside the description list
      container.find('dl dd:eq(0)').empty().html($('input[name=name]').val() || 'N/A');
      container.find('dl dd:eq(1)').empty().html($('input[name=desc]').val() || 'N/A');

    },
    uploadProgress: function(event, position, total, percentComplete) {
      var percentVal = percentComplete + '%';
      bar.width(percentVal)
    },
    complete: function(xhr) {
      var result = JSON.parse(xhr.responseText);

      // create an alert box inside the status area
      status.html('<div class="alert">'+
		  result.message +
		  '</div>');

      // put the color
      if (result.status == "error") {
	status.find('div').addClass("alert-error");
      } else if (result.status == "warning") {
	status.find('div').addClass("alert-block");
      } else if (result.status == "success") {
	status.find('div').addClass("alert-success");
      } else {
	status.find('div').addClass("alert-info");
      }

      // show button
      buttons.show();

      buttons.find('.reset').click(function () {
	$('#fileupload').each(function(){
	  this.reset();
	});
	container.hide();
	$('#fileupload').show();
      });
    }
  }); 
  
})();


